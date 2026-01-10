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
  final int sequence;
  
  IndexedAudioChunk({
    required this.bytes,
    required this.timestampStart,
    required this.timestampEnd,
    required this.sequence,
  });
}

class SynchronizedPlayerService {
  late YoutubePlayerController videoController;
  final AudioPlayer _translatedAudioPlayer = AudioPlayer();
  
  final List<IndexedAudioChunk> _audioIndex = [];
  ConcatenatingAudioSource? _playlist;
  
  // ✅ Stocker les positions réelles de début de chaque chunk
  final List<double> _chunkStartPositions = [];
  
  double _translatedVolume = 1.0;
  bool _originalMuted = false;
  
  bool _isSyncing = false;
  Timer? _syncTimer;
  bool _isDisposed = false;
  bool _translationComplete = false;
  
  bool _hasFirstChunk = false;
  bool _hasStarted = false;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;
  double _chunkDuration = 10.0;
  
  bool _wasPlaying = false;
  double _lastVideoPosition = 0.0;
  
  bool get isPlaying => videoController.value.isPlaying;
  Duration get position => videoController.value.position;
  bool get canSeek => _translationComplete;
  bool get hasFirstChunk => _hasFirstChunk;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalChunks => _totalChunks;
  int get availableChunks => _audioIndex.length;
  double get translatedVolume => _translatedVolume;
  bool get originalMuted => _originalMuted;
  
  bool get canNavigateNext => _hasStarted && _currentChunkIndex < _audioIndex.length - 1;
  bool get canNavigatePrevious => _hasStarted && _currentChunkIndex > 0;
  
  void initializeVideo(String videoId) {
    videoController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
        autoPlay: false,
        mute: false,
        enableCaption: false,
        controlsVisibleAtStart: false,
        hideControls: true,
        disableDragSeek: true,
        loop: false,
        forceHD: false,
      ),
    );
    
    _translatedAudioPlayer.setVolume(_translatedVolume);
    _startAggressiveSync();
  }
  
  void setTotalChunks(int total, double chunkDuration) {
    _totalChunks = total;
    _chunkDuration = chunkDuration;
    print('📊 Total: $_totalChunks chunks (${chunkDuration}s/chunk)');
  }
  
  Future<void> setTranslatedVolume(double volume) async {
    _translatedVolume = volume.clamp(0.0, 1.0);
    await _translatedAudioPlayer.setVolume(_translatedVolume);
    print('🔊 Volume traduit: ${(_translatedVolume * 100).toInt()}%');
  }
  
  Future<void> toggleOriginalAudio() async {
    _originalMuted = !_originalMuted;
    
    if (_originalMuted) {
      videoController.mute();
      print('🔇 Audio original coupé');
    } else {
      videoController.unMute();
      print('🔊 Audio original activé');
    }
  }
  
  void _startAggressiveSync() {
    _syncTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      if (_isSyncing) return;
      if (!_hasStarted) return;
      
      _checkPlayPauseState();
      _checkPositionJump();
      _updateCurrentChunk();
    });
  }
  
  void _checkPlayPauseState() {
    final isNowPlaying = videoController.value.isPlaying;
    final audioIsPlaying = _translatedAudioPlayer.playing;
    
    if (isNowPlaying != _wasPlaying) {
      if (isNowPlaying && !audioIsPlaying) {
        _translatedAudioPlayer.play();
      } else if (!isNowPlaying && audioIsPlaying) {
        _translatedAudioPlayer.pause();
      }
      _wasPlaying = isNowPlaying;
    }
  }
  
  void _checkPositionJump() {
    final currentVideoPos = videoController.value.position.inSeconds.toDouble();
    final positionDiff = (currentVideoPos - _lastVideoPosition).abs();
    
    if (positionDiff > 5.0) {
      print('🎯 Jump: ${_lastVideoPosition.toStringAsFixed(1)}s → ${currentVideoPos.toStringAsFixed(1)}s');
      _syncAudioToVideoPosition(currentVideoPos);
    }
    
    _lastVideoPosition = currentVideoPos;
  }
  
  void _updateCurrentChunk() {
    if (!_hasStarted || _audioIndex.isEmpty) return;
    
    final videoPos = videoController.value.position.inSeconds.toDouble();
    int newChunkIndex = (videoPos / _chunkDuration).floor();
    newChunkIndex = newChunkIndex.clamp(0, _audioIndex.length - 1);
    
    if (newChunkIndex != _currentChunkIndex) {
      _currentChunkIndex = newChunkIndex;
    }
  }
  
  Future<void> addAudioChunk(AudioChunk chunk) async {
    if (chunk.data.isEmpty || _isDisposed) return;
    
    try {
      final bytes = base64.decode(chunk.data);
      
      _audioIndex.add(IndexedAudioChunk(
        bytes: bytes,
        timestampStart: chunk.timestampStart,
        timestampEnd: chunk.timestampEnd,
        sequence: chunk.sequence,
      ));
      
      print('📦 Chunk #${chunk.sequence + 1} | ${chunk.timestampStart.toStringAsFixed(1)}s-${chunk.timestampEnd.toStringAsFixed(1)}s');
      
      if (_audioIndex.length == 1) {
        await _buildAudioPlaylist();
        _hasFirstChunk = true;
        
        // ✅ Stocker position du premier chunk
        _chunkStartPositions.add(0.0);
        
        print('✅ Premier chunk prêt');
      } else if (_playlist != null) {
        // ✅ ATTENDRE que le chunk soit ajouté à la playlist
        await _playlist!.add(_BytesAudioSource(bytes));
        
        // ✅ Puis obtenir la durée totale mise à jour
        await Future.delayed(Duration(milliseconds: 100));
        
        final currentDuration = _translatedAudioPlayer.duration;
        if (currentDuration != null) {
          final realPosition = currentDuration.inMilliseconds / 1000.0;
          _chunkStartPositions.add(realPosition);
          print('📍 Position réelle chunk ${_audioIndex.length}: ${realPosition.toStringAsFixed(1)}s');
        } else {
          // Fallback : estimation
          final estimatedPos = (_audioIndex.length - 1) * _chunkDuration;
          _chunkStartPositions.add(estimatedPos);
          print('⚠️ Estimation position chunk ${_audioIndex.length}: ${estimatedPos.toStringAsFixed(1)}s');
        }
      }
      
    } catch (e) {
      print('❌ Erreur chunk: $e');
    }
  }
  
  Future<void> _buildAudioPlaylist() async {
    try {
      _playlist = ConcatenatingAudioSource(
        children: [_BytesAudioSource(_audioIndex[0].bytes)],
      );
      await _translatedAudioPlayer.setAudioSource(_playlist!);
      print('🎵 Playlist OK');
    } catch (e) {
      print('❌ Erreur playlist: $e');
    }
  }
  
  Future<void> startPlayback() async {
    if (_hasStarted) return;
    if (!_hasFirstChunk) return;
    
    print('🎬 DÉMARRAGE');
    _hasStarted = true;
    _lastVideoPosition = 0.0;
    
    _isSyncing = true;
    
    videoController.play();
    print('▶️ Vidéo + audio original');
    
    await Future.delayed(Duration(milliseconds: 200));
    
    await _translatedAudioPlayer.play();
    print('▶️ Audio traduit');
    
    _wasPlaying = true;
    _isSyncing = false;
  }
  
  void markTranslationComplete() {
    _translationComplete = true;
    print('✅ Traduction complète');
  }
  
  Future<void> nextChunk() async {
    if (_currentChunkIndex >= _audioIndex.length - 1) {
      print('⚠️ Pas de chunk suivant');
      return;
    }
    
    print('\n⏭️ NEXT: ${_currentChunkIndex + 1} → ${_currentChunkIndex + 2}');
    await _seekToChunk(_currentChunkIndex + 1);
  }
  
  Future<void> previousChunk() async {
    if (_currentChunkIndex <= 0) {
      print('⚠️ Déjà au début');
      return;
    }
    
    print('\n⏮️ PREV: ${_currentChunkIndex + 1} → $_currentChunkIndex');
    await _seekToChunk(_currentChunkIndex - 1);
  }
  
  Future<void> _seekToChunk(int chunkIndex) async {
    if (chunkIndex < 0 || chunkIndex >= _audioIndex.length) return;
    
    final chunk = _audioIndex[chunkIndex];
    print('🎯 === SEEK CHUNK ${chunkIndex + 1}/${_audioIndex.length} ===');
    
    _isSyncing = true;
    
    final wasPlayingBefore = videoController.value.isPlaying;
    
    // Pause tout
    if (wasPlayingBefore) {
      videoController.pause();
      await _translatedAudioPlayer.pause();
      await Future.delayed(Duration(milliseconds: 200));
    }
    
    // Seek vidéo
    final targetVideoPos = Duration(milliseconds: (chunk.timestampStart * 1000).toInt());
    videoController.seekTo(targetVideoPos);
    print('📹 Vidéo → ${chunk.timestampStart.toStringAsFixed(1)}s');
    
    await Future.delayed(Duration(milliseconds: 800));
    
    // ✅ Seek audio avec position réelle stockée
    double targetAudioPos;
    if (chunkIndex < _chunkStartPositions.length) {
      targetAudioPos = _chunkStartPositions[chunkIndex];
      print('🎵 Audio → ${targetAudioPos.toStringAsFixed(1)}s (position réelle)');
    } else {
      // Fallback
      targetAudioPos = chunkIndex * _chunkDuration;
      print('⚠️ Audio → ${targetAudioPos.toStringAsFixed(1)}s (estimation)');
    }
    
    try {
      await _translatedAudioPlayer.seek(
        Duration(milliseconds: (targetAudioPos * 1000).toInt())
      );
      print('✅ Audio positionné');
    } catch (e) {
      print('❌ Erreur seek audio: $e');
    }
    
    _lastVideoPosition = chunk.timestampStart;
    _currentChunkIndex = chunkIndex;
    
    await Future.delayed(Duration(milliseconds: 500));
    
    // Reprendre
    if (wasPlayingBefore) {
      videoController.play();
      await Future.delayed(Duration(milliseconds: 200));
      await _translatedAudioPlayer.play();
      print('▶️ Reprise lecture');
    }
    
    await Future.delayed(Duration(milliseconds: 500));
    
    _isSyncing = false;
    print('✅ === SEEK OK ===\n');
  }
  
  Future<void> seekTo(Duration position) async {
    if (!_translationComplete) return;
    
    final targetSeconds = position.inSeconds.toDouble();
    int targetChunkIndex = (targetSeconds / _chunkDuration).floor();
    targetChunkIndex = targetChunkIndex.clamp(0, _audioIndex.length - 1);
    
    await _seekToChunk(targetChunkIndex);
  }
  
  Future<void> _syncAudioToVideoPosition(double targetSeconds) async {
    if (_audioIndex.isEmpty || _playlist == null) return;
    
    int targetChunkIndex = -1;
    double offsetInTargetChunk = 0.0;
    
    for (int i = 0; i < _audioIndex.length; i++) {
      final chunk = _audioIndex[i];
      
      if (targetSeconds >= chunk.timestampStart && targetSeconds < chunk.timestampEnd) {
        targetChunkIndex = i;
        offsetInTargetChunk = targetSeconds - chunk.timestampStart;
        break;
      }
    }
    
    if (targetChunkIndex == -1) {
      double minDistance = double.infinity;
      for (int i = 0; i < _audioIndex.length; i++) {
        final chunk = _audioIndex[i];
        final distance = (chunk.timestampStart - targetSeconds).abs();
        if (distance < minDistance) {
          minDistance = distance;
          targetChunkIndex = i;
          offsetInTargetChunk = 0.0;
        }
      }
    }
    
    if (targetChunkIndex >= 0) {
      // ✅ Utiliser position réelle si disponible
      double targetPosition;
      if (targetChunkIndex < _chunkStartPositions.length) {
        targetPosition = _chunkStartPositions[targetChunkIndex] + offsetInTargetChunk;
      } else {
        targetPosition = targetChunkIndex * _chunkDuration + offsetInTargetChunk;
      }
      
      try {
        await _translatedAudioPlayer.seek(
          Duration(milliseconds: (targetPosition * 1000).toInt())
        );
      } catch (e) {
        print('❌ Erreur sync: $e');
      }
    }
  }
  
  Future<void> playPause() async {
    if (!_hasStarted) return;
    
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
    
    await _translatedAudioPlayer.play();
    await Future.delayed(Duration(milliseconds: 50));
    videoController.play();
    
    _wasPlaying = true;
    _isSyncing = false;
  }
  
  Future<void> pause() async {
    print('⏸️ Pause');
    _isSyncing = true;
    
    videoController.pause();
    await Future.delayed(Duration(milliseconds: 50));
    await _translatedAudioPlayer.pause();
    
    _wasPlaying = false;
    _isSyncing = false;
  }
  
  Future<void> goToStart() async {
    print('🏠 Début');
    await _seekToChunk(0);
  }
  
  void dispose() {
    print('🗑️ Dispose');
    _isDisposed = true;
    _syncTimer?.cancel();
    videoController.dispose();
    _translatedAudioPlayer.dispose();
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