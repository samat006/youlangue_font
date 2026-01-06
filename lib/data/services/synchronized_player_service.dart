// lib/data/services/synchronized_player_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../models/translation_model.dart';

class IndexedAudioChunk {
  final Uint8List bytes;
  final double timestampStart;
  final double timestampEnd;
  
  IndexedAudioChunk({
    required this.bytes,
    required this.timestampStart,
    required this.timestampEnd,
  });
}

class SynchronizedPlayerService {
  late YoutubePlayerController videoController;
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  // ✅ INDEX DES CHUNKS
  final List<IndexedAudioChunk> _audioIndex = [];
  ConcatenatingAudioSource? _playlist;
  
  bool _isSyncing = false;
  Timer? _syncTimer;
  bool _isDisposed = false;
  bool _translationComplete = false;
  
  // Buffer initial
  int _minChunksToStart = 3;
  bool _hasStarted = false;
  
  bool get isPlaying => videoController.value.isPlaying;
  Duration get position => videoController.value.position;
  bool get canSeek => _translationComplete; // ✅ Seek autorisé seulement si complet
  
  void initializeVideo(String videoId) {
    videoController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
        autoPlay: false,
        mute: true,
        enableCaption: false,
        controlsVisibleAtStart: false,
        disableDragSeek: false,
      ),
    );
    
    _startVideoListener();
    _startPositionSync();
  }
  
  void _startVideoListener() {
    videoController.addListener(() {
      if (_isDisposed || _isSyncing) return;
      
      final videoIsPlaying = videoController.value.isPlaying;
      final audioIsPlaying = _audioPlayer.playing;
      
      if (videoIsPlaying && !audioIsPlaying && _hasStarted) {
        _audioPlayer.play();
      } else if (!videoIsPlaying && audioIsPlaying) {
        _audioPlayer.pause();
      }
    });
  }
  
  void _startPositionSync() {
    _syncTimer = Timer.periodic(Duration(milliseconds: 500), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      _checkAndFixSync();
    });
  }
  
  void _checkAndFixSync() {
    if (_playlist == null || _isSyncing || !_hasStarted) return;
    
    final videoPos = videoController.value.position.inSeconds.toDouble();
    final audioPos = _audioPlayer.position.inSeconds.toDouble();
    final drift = (videoPos - audioPos).abs();
    
    if (drift > 1.0 && videoController.value.isPlaying) {
      print('⚠️ Drift: ${drift.toStringAsFixed(1)}s → Resync');
      _syncAudioToVideoPosition(videoPos);
    }
  }
  
  // ✅ AJOUTER UN CHUNK AVEC TIMESTAMP
  Future<void> addAudioChunk(AudioChunk chunk) async {
    if (chunk.data.isEmpty || _isDisposed) return;
    
    try {
      final bytes = base64.decode(chunk.data);
      
      // ✅ Indexer avec timestamp
      _audioIndex.add(IndexedAudioChunk(
        bytes: bytes,
        timestampStart: chunk.timestampStart,
        timestampEnd: chunk.timestampEnd,
      ));
      
      print('📦 Chunk #${chunk.sequence} [${chunk.timestampStart.toStringAsFixed(1)}s - ${chunk.timestampEnd.toStringAsFixed(1)}s]');
      
      // Créer la playlist au premier chunk
      if (_audioIndex.length == 1) {
        await _buildAudioPlaylist();
      } else if (_playlist != null) {
        await _playlist!.add(_BytesAudioSource(bytes));
      }
      
      // ✅ Démarrer automatiquement après buffer minimum
      if (!_hasStarted && _audioIndex.length >= _minChunksToStart) {
        await _startPlayback();
      }
      
    } catch (e) {
      print('❌ Erreur ajout chunk: $e');
    }
  }
  
  Future<void> _buildAudioPlaylist() async {
    try {
      _playlist = ConcatenatingAudioSource(
        children: [_BytesAudioSource(_audioIndex[0].bytes)],
      );
      
      await _audioPlayer.setAudioSource(_playlist!);
      print('🎵 Playlist créée');
      
    } catch (e) {
      print('❌ Erreur playlist: $e');
    }
  }
  
  Future<void> _startPlayback() async {
    print('🎬 Démarrage lecture (${_audioIndex.length} chunks en buffer)');
    _hasStarted = true;
    await play();
  }
  
  void markTranslationComplete() {
    _translationComplete = true;
    print('✅ Traduction complète - Seek activé');
  }
  
  // ✅ SEEK INTELLIGENT AVEC INDEX
  Future<void> seekTo(Duration position) async {
    if (!_translationComplete) {
      print('⚠️ Seek désactivé pendant traduction');
      return;
    }
    
    print('⏩ Seek → ${position.inSeconds}s');
    await _syncAudioToVideoPosition(position.inSeconds.toDouble());
    
    _isSyncing = true;
    videoController.seekTo(position);
    
    await Future.delayed(Duration(milliseconds: 300));
    _isSyncing = false;
  }
  
  Future<void> _syncAudioToVideoPosition(double targetSeconds) async {
    if (_audioIndex.isEmpty) return;
    
    // ✅ Chercher le chunk qui correspond à cette position
    int targetChunkIndex = -1;
    double accumulatedDuration = 0.0;
    
    for (int i = 0; i < _audioIndex.length; i++) {
      final chunk = _audioIndex[i];
      
      if (targetSeconds >= chunk.timestampStart && targetSeconds < chunk.timestampEnd) {
        targetChunkIndex = i;
        
        // Offset dans le chunk
        final offsetInChunk = targetSeconds - chunk.timestampStart;
        accumulatedDuration += offsetInChunk;
        break;
      }
      
      if (i < targetChunkIndex) {
        accumulatedDuration += (chunk.timestampEnd - chunk.timestampStart);
      }
    }
    
    if (targetChunkIndex >= 0) {
      print('🎯 Seek audio → chunk $targetChunkIndex @ ${accumulatedDuration.toStringAsFixed(1)}s');
      
      try {
        await _audioPlayer.seek(Duration(milliseconds: (accumulatedDuration * 1000).toInt()));
      } catch (e) {
        print('⚠️ Audio seek failed: $e');
      }
    } else {
      print('⚠️ Position ${targetSeconds}s pas encore disponible');
    }
  }
  
  Future<void> playPause() async {
    if (!_hasStarted) {
      print('⚠️ Attendre le buffer initial');
      return;
    }
    
    if (videoController.value.isPlaying) {
      await pause();
    } else {
      await play();
    }
  }
  
  Future<void> play() async {
    if (!_hasStarted) return;
    
    print('▶️ Play');
    _isSyncing = true;
    
    videoController.play();
    await _audioPlayer.play();
    
    _isSyncing = false;
  }
  
  Future<void> pause() async {
    print('⏸️ Pause');
    _isSyncing = true;
    
    videoController.pause();
    await _audioPlayer.pause();
    
    _isSyncing = false;
  }
  
  Future<void> seekForward(int seconds) async {
    if (!_translationComplete) return;
    final newPos = videoController.value.position + Duration(seconds: seconds);
    await seekTo(newPos);
  }
  
  Future<void> seekBackward(int seconds) async {
    if (!_translationComplete) return;
    final current = videoController.value.position;
    final newPos = current - Duration(seconds: seconds);
    await seekTo(newPos.isNegative ? Duration.zero : newPos);
  }
  
  void dispose() {
    _isDisposed = true;
    _syncTimer?.cancel();
    videoController.dispose();
    _audioPlayer.dispose();
  }
}

class _BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  
  _BytesAudioSource(this._bytes);
  
  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: 'audio/mpeg',
    );
  }
}