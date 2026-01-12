// lib/data/services/synchronized_player_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path_provider/path_provider.dart';

import '../models/translation_model.dart';

class IndexedAudioChunk {
  final Uint8List bytes;
  final String? filePath;  // ✅ NOUVEAU : fichier sur disque (Android)
  final double timestampStart;
  final double timestampEnd;
  final int sequence;
  
  IndexedAudioChunk({
    required this.bytes,
    this.filePath,
    required this.timestampStart,
    required this.timestampEnd,
    required this.sequence,
  });
}

class SynchronizedPlayerService extends ChangeNotifier {
  YoutubePlayerController? _ytController;
  VideoPlayerController? nativeVideoController;
  
  final AudioPlayer _translatedAudioPlayer = AudioPlayer();
  final AudioPlayer _originalAudioPlayer = AudioPlayer();
  
  final List<IndexedAudioChunk> _audioIndex = [];
  ConcatenatingAudioSource? _playlist;
  final List<double> _chunkStartPositions = [];
  
  Directory? _cacheDir;  // ✅ NOUVEAU
  final List<String> _tempFiles = [];  // ✅ NOUVEAU : cleanup

  bool _isNativeVideoMode = false;
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
  
  // Getters (inchangés)
  YoutubePlayerController get videoController => _ytController!; 
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
  
  // ✅ NOUVEAU : Init cache (Android uniquement)
  Future<void> _initCacheIfNeeded() async {
    if (Platform.isAndroid && _cacheDir == null) {
      try {
        final tempDir = await getTemporaryDirectory();
        _cacheDir = Directory('${tempDir.path}/voxtube_audio');
        if (!await _cacheDir!.exists()) {
          await _cacheDir!.create(recursive: true);
        }
        print('📁 Cache Android: ${_cacheDir!.path}');
      } catch (e) {
        print('❌ Erreur cache: $e');
      }
    }
  }
  
  void initializeVideo(String videoId) async {
    _isNativeVideoMode = false;
    
    await _initCacheIfNeeded();  // ✅ NOUVEAU
    _configureAudioSession();
    
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

  Future<void> initializeNativeVideo(String videoUrl) async {
    _isNativeVideoMode = true;
    
    print('🎬 Initialisation vidéo native: $videoUrl');
    
    await _initCacheIfNeeded();  // ✅ NOUVEAU
    await _configureAudioSession();
    
    nativeVideoController = VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
    );
    
    try {
      await nativeVideoController!.initialize();
      await nativeVideoController!.setVolume(0.0);
      notifyListeners();
      print('✅ Vidéo native initialisée');
    } catch (e) {
      print('❌ Erreur vidéo: $e');
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
  
  // ✅ MODIFIÉ : Audio original (Android = fichier, iOS = StreamAudioSource)
  Future<void> loadOriginalAudio(String base64Data) async {
    try {
      print('🎵 Chargement audio original...');
      final bytes = base64.decode(base64Data);
      
      if (Platform.isAndroid) {
        // ✅ ANDROID : Écrire sur disque
        await _initCacheIfNeeded();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${_cacheDir!.path}/original_$timestamp.mp3');
        await file.writeAsBytes(bytes);
        _tempFiles.add(file.path);
        
        await _originalAudioPlayer.setAudioSource(
          AudioSource.uri(Uri.file(file.path))
        );
        print('✅ Audio original chargé (Android fichier): ${file.path}');
      } else {
        // ✅ iOS : StreamAudioSource (comme avant)
        final source = _BytesAudioSource(bytes);
        await _originalAudioPlayer.setAudioSource(source);
        print('✅ Audio original chargé (iOS mémoire): ${bytes.length} bytes');
      }
      
      await _originalAudioPlayer.setVolume(_originalVolume);
      _originalAudioLoaded = true;
      
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
  
  // ✅ MODIFIÉ : Chunks (Android = fichiers, iOS = StreamAudioSource)
  Future<void> addAudioChunk(AudioChunk chunk) async {
    if (chunk.data.isEmpty || _isDisposed) return;
    
    try {
      final bytes = base64.decode(chunk.data);
      String? filePath;
      
      if (Platform.isAndroid) {
        // ✅ ANDROID : Écrire chunk sur disque
        await _initCacheIfNeeded();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${_cacheDir!.path}/chunk_${chunk.sequence}_$timestamp.mp3');
        await file.writeAsBytes(bytes);
        filePath = file.path;
        _tempFiles.add(filePath);
        print('💾 Chunk #${chunk.sequence + 1} écrit: $filePath');
      }
      
      _audioIndex.add(IndexedAudioChunk(
        bytes: bytes,
        filePath: filePath,
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
        
        if (Platform.isAndroid) {
          // ✅ ANDROID : Ajouter URI
          await _playlist!.add(
            AudioSource.uri(Uri.file(_audioIndex.last.filePath!))
          );
        } else {
          // ✅ iOS : Ajouter StreamAudioSource
          await _playlist!.add(_BytesAudioSource(bytes));
        }
      }
      
    } catch (e) {
      print('❌ Erreur chunk: $e');
    }
  }
  
  // ✅ MODIFIÉ : Playlist (Android = URI, iOS = StreamAudioSource)
  Future<void> _buildAudioPlaylist() async {
    try {
      final firstChunk = _audioIndex[0];
      
      if (Platform.isAndroid) {
        // ✅ ANDROID : Playlist avec URI
        _playlist = ConcatenatingAudioSource(
          useLazyPreparation: true,
          children: [
            AudioSource.uri(Uri.file(firstChunk.filePath!))
          ],
        );
        print('🎵 Playlist créée (Android URI)');
      } else {
        // ✅ iOS : Playlist avec StreamAudioSource
        _playlist = ConcatenatingAudioSource(
          children: [_BytesAudioSource(firstChunk.bytes)],
        );
        print('🎵 Playlist créée (iOS mémoire)');
      }
      
      await _translatedAudioPlayer.setAudioSource(_playlist!);
      
    } catch (e) {
      print('❌ Erreur playlist: $e');
    }
  }
  
  // TOUTES LES AUTRES MÉTHODES RESTENT IDENTIQUES
  
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
    
    if (_isNativeVideoMode) {
      await nativeVideoController?.play();
    } else {
      _ytController?.play();
    }
    print('▶️ Vidéo');
    
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
    
    if (_isNativeVideoMode) {
      await nativeVideoController?.pause();
    } else {
      _ytController?.pause();
    }
    print('⏸️ Vidéo');
    _lastVideoPlayingState = false;
    
    await Future.delayed(const Duration(milliseconds: 100));
    
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
  
  // ✅ NOUVEAU : Cleanup fichiers temporaires (Android)
  Future<void> _cleanupTempFiles() async {
    if (Platform.isAndroid && _tempFiles.isNotEmpty) {
      try {
        print('🗑️ Nettoyage ${_tempFiles.length} fichiers Android...');
        for (final path in _tempFiles) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
            }
          } catch (e) {
            // Ignorer erreurs individuelles
          }
        }
        _tempFiles.clear();
        print('✅ Nettoyage OK');
      } catch (e) {
        print('⚠️ Erreur cleanup: $e');
      }
    }
  }
  
  @override
  void dispose() {
    print('🗑️ Dispose PlayerService');
    _isDisposed = true;
    _syncTimer?.cancel();
    
    if (_isNativeVideoMode) {
      nativeVideoController?.dispose();
    } else {
      _ytController?.dispose();
    }
    
    _translatedAudioPlayer.dispose();
    _originalAudioPlayer.dispose();
    
    // ✅ Cleanup async
    _cleanupTempFiles();
    
    super.dispose();
  }

  Future<void> _configureAudioSession() async {
    try {
      print('🔊 Configuration audio session...');
      
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
        avAudioSessionSetActiveOptions: AVAudioSessionSetActiveOptions.none,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.movie,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
        androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
        androidWillPauseWhenDucked: false,
      ));
      
      print('✅ Audio session configurée');
    } catch (e) {
      print('⚠️ Erreur config audio: $e');
    }
  }
}

// ✅ StreamAudioSource GARDÉ pour iOS
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