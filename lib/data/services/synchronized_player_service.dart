// lib/data/services/synchronized_player_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart'; // Pour ChangeNotifier
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:video_player/video_player.dart'; // Pour les fichiers uploadés/natifs

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

class SynchronizedPlayerService extends ChangeNotifier {
  // Contrôleurs
  YoutubePlayerController? _ytController; // Ancien 'videoController', maintenant interne et nullable
  VideoPlayerController? nativeVideoController; // Contrôleur pour les fichiers natifs/uploadés
  
  final AudioPlayer _translatedAudioPlayer = AudioPlayer();
  final AudioPlayer _originalAudioPlayer = AudioPlayer();
  
  final List<IndexedAudioChunk> _audioIndex = [];
  ConcatenatingAudioSource? _playlist;
  final List<double> _chunkStartPositions = [];

  // Indicateurs d'état
  bool _isNativeVideoMode = false; // Vrai si c'est un fichier uploadé
  bool _isDisposed = false;
  bool _translationComplete = false;
  bool _originalAudioLoaded = false;
  bool _hasFirstChunk = false;
  bool _hasStarted = false;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;
  double _chunkDuration = 10.0;
  
  double _translatedVolume = 1.0;
  double _originalVolume = 0.5;
  
  Timer? _syncTimer;
  bool _lastVideoPlayingState = false;
  
  // Getters
  
  // Expose le contrôleur YT si nécessaire (pour PlayerScreen qui utilise YoutubePlayer)
  YoutubePlayerController get videoController => _ytController!; 
  
  // Expose le contrôleur natif (pour PlayerScreen qui utilise VideoPlayer)
  VideoPlayerController get localVideoController => nativeVideoController!;
  bool get isLocalVideoLoaded => nativeVideoController?.value.isInitialized ?? false;

  bool get isPlaying => _isNativeVideoMode 
    ? (nativeVideoController?.value.isPlaying ?? false)
    : (_ytController?.value.isPlaying ?? false);
    
  Duration get position => _isNativeVideoMode 
    ? (nativeVideoController?.value.position ?? Duration.zero)
    : (_ytController?.value.position ?? Duration.zero);
    
  bool get isNativeVideoMode => _isNativeVideoMode;
  bool get canSeek => _translationComplete;
  bool get hasFirstChunk => _hasFirstChunk;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalChunks => _totalChunks;
  int get availableChunks => _audioIndex.length;
  double get translatedVolume => _translatedVolume;
  double get originalVolume => _originalVolume;
  bool get canNavigateNext => _hasStarted && _currentChunkIndex < _audioIndex.length - 1;
  bool get canNavigatePrevious => _hasStarted && _currentChunkIndex > 0;
  
  void initializeVideo(String videoId) {
    _isNativeVideoMode = false; // Mode YouTube
    _ytController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: false,
        mute: true,
        enableCaption: false,
        controlsVisibleAtStart: false,
        hideControls: true,
        disableDragSeek: true,
        loop: false,
        forceHD: false,
      ),
    );
    
    _translatedAudioPlayer.setVolume(_translatedVolume);
    _originalAudioPlayer.setVolume(_originalVolume);
    
    _startPlayPauseSync();
  }
  
  // ✅ NOUVELLE MÉTHODE : Initialisation vidéo native
  Future<void> initializeNativeVideo(String videoUrl) async {
    _isNativeVideoMode = true;
    
    print('🎬 Initialisation vidéo native: $videoUrl');
    
    nativeVideoController = VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
    );
    
    try {
      await nativeVideoController!.initialize();
      await nativeVideoController!.setVolume(0.0);
      notifyListeners(); // Informe PlayerScreen que la vidéo est chargée
      print('✅ Vidéo native initialisée');
    } catch (e) {
      print('❌ Erreur chargement vidéo native: $e');
      // Si la vidéo ne charge pas, elle reste en mode "audio seulement" (isLocalVideoLoaded = false)
      nativeVideoController = null;
    }
    
    _translatedAudioPlayer.setVolume(_translatedVolume);
    _originalAudioPlayer.setVolume(_originalVolume);
    
    _startPlayPauseSync();
  }

  void _startPlayPauseSync() {
    _syncTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      if (!_hasStarted) return;
      
      // Utilisation du getter isPlaying unifié
      final videoPlaying = isPlaying; 
      
      if (videoPlaying != _lastVideoPlayingState) {
        _lastVideoPlayingState = videoPlaying;
        
        if (videoPlaying) {
          if (!_translatedAudioPlayer.playing) {
            _translatedAudioPlayer.play();
            print('🔄 Audio traduit -> Play');
          }
          if (_originalAudioLoaded && !_originalAudioPlayer.playing) {
            _originalAudioPlayer.play();
            print('🔄 Audio original -> Play');
          }
        } else {
          if (_translatedAudioPlayer.playing) {
            _translatedAudioPlayer.pause();
            print('🔄 Audio traduit -> Pause');
          }
          if (_originalAudioLoaded && _originalAudioPlayer.playing) {
            _originalAudioPlayer.pause();
            print('🔄 Audio original -> Pause');
          }
        }
      }
    });
  }
  
  void setTotalChunks(int total, double chunkDuration) {
    _totalChunks = total;
    _chunkDuration = chunkDuration;
    print('📊 Total: $_totalChunks chunks (${chunkDuration}s/chunk)');
  }
  
  Future<void> loadOriginalAudio(String base64Data) async {
    try {
      print('🎵 Chargement audio original...');
      final bytes = base64.decode(base64Data);
      final source = _BytesAudioSource(bytes);
      
      await _originalAudioPlayer.setAudioSource(source);
      await _originalAudioPlayer.setVolume(_originalVolume);
      
      _originalAudioLoaded = true;
      print('✅ Audio original chargé (${bytes.length} bytes)');
    } catch (e) {
      print('❌ Erreur audio original: $e');
    }
  }
  
  Future<void> setTranslatedVolume(double volume) async {
    _translatedVolume = volume.clamp(0.0, 1.0);
    await _translatedAudioPlayer.setVolume(_translatedVolume);
    print('🔊 Volume traduit: ${(_translatedVolume * 100).toInt()}%');
  }
  
  Future<void> setOriginalVolume(double volume) async {
    _originalVolume = volume.clamp(0.0, 1.0);
    await _originalAudioPlayer.setVolume(_originalVolume);
    print('🔊 Volume original: ${(_originalVolume * 100).toInt()}%');
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
        _chunkStartPositions.add(0.0);
        print('✅ Premier chunk prêt');
      } else if (_playlist != null) {
        double cumulativePosition = 0.0;
        for (int i = 0; i < _audioIndex.length - 1; i++) {
          final prevChunk = _audioIndex[i];
          final duration = prevChunk.timestampEnd - prevChunk.timestampStart;
          cumulativePosition += duration;
        }
        
        _chunkStartPositions.add(cumulativePosition);
        await _playlist!.add(_BytesAudioSource(bytes));
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
      print('🎵 Playlist créée');
    } catch (e) {
      print('❌ Erreur playlist: $e');
    }
  }
  
  Future<void> startPlayback() async {
    if (_hasStarted) {
      print('⚠️ Déjà démarré');
      return;
    }
    if (!_hasFirstChunk) {
      print('⚠️ Pas de chunk');
      return;
    }
    
    print('\n🎬 ========== DÉMARRAGE ==========');
    _hasStarted = true;
    
    try {
      // 1. POSITIONNER À ZÉRO
      print('1️⃣ Positionnement à 0...');
      await _translatedAudioPlayer.seek(Duration.zero);
      if (_originalAudioLoaded) {
        await _originalAudioPlayer.seek(Duration.zero);
      }
      
      if (_isNativeVideoMode) {
        await nativeVideoController?.seekTo(Duration.zero);
      } else {
        _ytController?.seekTo(Duration.zero);
      }
      
      await Future.delayed(const Duration(milliseconds: 500));
      
      // 2. DÉMARRER AUDIOS
      print('2️⃣ Démarrage audios...');
      await _translatedAudioPlayer.play();
      print('   ✅ Audio traduit démarré');
      
      if (_originalAudioLoaded) {
        await _originalAudioPlayer.play();
        print('   ✅ Audio original démarré');
      } else {
        print('   ⚠️ Audio original non chargé');
      }
      
      await Future.delayed(const Duration(milliseconds: 300));
      
      // 3. DÉMARRER VIDÉO
      print('3️⃣ Démarrage vidéo...');
      if (_isNativeVideoMode) {
        await nativeVideoController?.play();
      } else {
        _ytController?.play();
      }
      print('   ✅ Vidéo démarrée');
      
      _lastVideoPlayingState = true;
      
      print('========== DÉMARRAGE OK ==========\n');
      
    } catch (e) {
      print('❌ Erreur démarrage: $e');
    }
  }
  
  void markTranslationComplete() {
    _translationComplete = true;
    print('✅ Traduction complète');
  }
  
  Future<void> playPause() async {
    if (!_hasStarted) return;
    
    if (isPlaying) {
      await pause();
    } else {
      await play();
    }
  }
  
  Future<void> play() async {
    if (!_hasStarted) return;
    
    print('\n▶️ ===== PLAY =====');
    
    // Vidéo
    if (_isNativeVideoMode) {
      await nativeVideoController?.play();
    } else {
      _ytController?.play();
    }
    print('▶️ Vidéo');
    
    // Audios
    await _translatedAudioPlayer.play();
    print('▶️ Audio traduit');
    
    if (_originalAudioLoaded) {
      await _originalAudioPlayer.play();
      print('▶️ Audio original');
    }
    
    await Future.delayed(const Duration(milliseconds: 100));
   
    _lastVideoPlayingState = true;
    
    print('===== PLAY OK =====\n');
  }
  
  Future<void> pause() async {
    print('\n⏸️ ===== PAUSE =====');
    
    // Vidéo d'abord
    if (_isNativeVideoMode) {
      await nativeVideoController?.pause();
    } else {
      _ytController?.pause();
    }
    print('⏸️ Vidéo');
    _lastVideoPlayingState = false;
    
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Audios ensuite
    await _translatedAudioPlayer.pause();
    print('⏸️ Audio traduit');
    
    if (_originalAudioLoaded) {
      await _originalAudioPlayer.pause();
      print('⏸️ Audio original');
    }
    
    print('===== PAUSE OK =====\n');
  }
  
  Future<void> nextChunk() async {
    if (_currentChunkIndex >= _audioIndex.length - 1) {
      print('⚠️ Dernier chunk');
      return;
    }
    
    print('\n⏭️ NEXT: ${_currentChunkIndex + 1} -> ${_currentChunkIndex + 2}');
    await _seekToChunk(_currentChunkIndex + 1);
  }
  
  Future<void> previousChunk() async {
    if (_currentChunkIndex <= 0) {
      print('⚠️ Premier chunk');
      return;
    }
    
    print('\n⏮️ PREV: ${_currentChunkIndex + 1} -> $_currentChunkIndex');
    await _seekToChunk(_currentChunkIndex - 1);
  }
  
  Future<void> _seekToChunk(int chunkIndex) async {
    if (chunkIndex < 0 || chunkIndex >= _audioIndex.length) return;
    
    final chunk = _audioIndex[chunkIndex];
    print('\n🎯 ===== SEEK CHUNK ${chunkIndex + 1}/${_audioIndex.length} =====');
    
    final wasPlaying = isPlaying;
    
    // 1. PAUSE
    if (wasPlaying) {
      if (_isNativeVideoMode) {
        await nativeVideoController?.pause();
      } else {
        _ytController?.pause();
      }
      await _translatedAudioPlayer.pause();
      if (_originalAudioLoaded) await _originalAudioPlayer.pause();
      print('⏸️ Tout en pause');
      await Future.delayed(const Duration(milliseconds: 200));
    }
    
    // 2. SEEK
    final duration = Duration(milliseconds: (chunk.timestampStart * 1000).toInt());

    if (_isNativeVideoMode) {
      await nativeVideoController?.seekTo(duration);
    } else {
      _ytController?.seekTo(duration);
    }
    print('📹 Vidéo -> ${chunk.timestampStart.toStringAsFixed(1)}s');
    
    if (chunkIndex < _chunkStartPositions.length) {
      final audioPos = _chunkStartPositions[chunkIndex];
      await _translatedAudioPlayer.seek(Duration(milliseconds: (audioPos * 1000).toInt()));
      print('🎵 Audio traduit -> ${audioPos.toStringAsFixed(1)}s');
    }
    
    if (_originalAudioLoaded) {
      await _originalAudioPlayer.seek(Duration(milliseconds: (chunk.timestampStart * 1000).toInt()));
      print('🎵 Audio original -> ${chunk.timestampStart.toStringAsFixed(1)}s');
    }
    
    _currentChunkIndex = chunkIndex;
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    // 3. REPRENDRE
    if (wasPlaying) {
      await _translatedAudioPlayer.play();
      if (_originalAudioLoaded) await _originalAudioPlayer.play();
      await Future.delayed(const Duration(milliseconds: 100));
      if (_isNativeVideoMode) {
        await nativeVideoController?.play();
      } else {
        _ytController?.play();
      }
      _lastVideoPlayingState = true;
      print('▶️ Reprise');
    }
    
    print('===== SEEK OK =====\n');
  }
  
  Future<void> seekTo(Duration position) async {
    if (!_translationComplete) return;
    
    final targetSeconds = position.inSeconds.toDouble();
    int targetChunkIndex = (targetSeconds / _chunkDuration).floor();
    targetChunkIndex = targetChunkIndex.clamp(0, _audioIndex.length - 1);
    
    await _seekToChunk(targetChunkIndex);
  }
  
  Future<void> goToStart() async {
    print('🏠 Retour au début');
    await _seekToChunk(0);
  }
  
  @override
  void dispose() {
    print('🗑️ Dispose PlayerService');
    _isDisposed = true;
    _syncTimer?.cancel();
    
    // Dispose conditionnel
    if (_isNativeVideoMode) {
      nativeVideoController?.dispose();
    } else {
      _ytController?.dispose();
    }
    
    _translatedAudioPlayer.dispose();
    _originalAudioPlayer.dispose();
    super.dispose();
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