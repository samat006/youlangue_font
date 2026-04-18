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
  final String? filePath;
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

  Directory? _cacheDir;
  final List<String> _tempFiles = [];

  bool _isNativeVideoMode = false;
  bool _isDisposed = false;
  bool _translationComplete = false;
  bool _originalAudioLoaded = false;
  bool _hasFirstChunk = false;
  bool _hasStarted = false;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;

  double _translatedVolume = 1.0;
  double _originalVolume = 0.5;

  Timer? _syncTimer;
  bool _lastVideoPlayingState = false;

  YoutubePlayerController get videoController => _ytController!;
  VideoPlayerController get localVideoController => nativeVideoController!;
  bool get isLocalVideoLoaded =>
      nativeVideoController?.value.isInitialized ?? false;
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
  bool get canNavigateNext =>
      _hasStarted && _currentChunkIndex < _audioIndex.length - 1;
  bool get canNavigatePrevious => _hasStarted && _currentChunkIndex > 0;

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

    await _initCacheIfNeeded();
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

    await _initCacheIfNeeded();
    await _configureAudioSession();

    nativeVideoController =
        VideoPlayerController.networkUrl(Uri.parse(videoUrl));

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
    _syncTimer =
        Timer.periodic(const Duration(milliseconds: 80), (timer) async {
      if (_isDisposed) {
        timer.cancel();
        return;
      }

      if (!_hasStarted || _audioIndex.isEmpty) return;

      final videoPlaying = isPlaying;

      if (videoPlaying != _lastVideoPlayingState) {
        _lastVideoPlayingState = videoPlaying;

        if (videoPlaying) {
          if (!_translatedAudioPlayer.playing) {
            await _translatedAudioPlayer.play();
          }
          if (_originalAudioLoaded && !_originalAudioPlayer.playing) {
            await _originalAudioPlayer.play();
          }
        } else {
          if (_translatedAudioPlayer.playing) {
            await _translatedAudioPlayer.pause();
          }
          if (_originalAudioLoaded && _originalAudioPlayer.playing) {
            await _originalAudioPlayer.pause();
          }
        }
      }

      final t = position.inMilliseconds / 1000.0;

      int index = _audioIndex.lastIndexWhere(
        (c) => c.timestampStart <= t && t < c.timestampEnd,
      );

      if (index < 0 && t >= 0) {
        index = 0;
      }
      if (index >= _audioIndex.length) {
        index = _audioIndex.length - 1;
      }

      if (index != _currentChunkIndex && index >= 0) {
        await _playChunk(index, videoPlaying: videoPlaying);
      }
    });
  }

  void setTotalChunks(int total, double _) {
    _totalChunks = total;
    print('📊 Total segments Whisper: $_totalChunks');
  }

  Future<void> loadOriginalAudio(String base64Data) async {
    try {
      print('🎵 Chargement audio original...');
      final bytes = base64.decode(base64Data);

      if (Platform.isAndroid) {
        await _initCacheIfNeeded();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file = File('${_cacheDir!.path}/original_$timestamp.mp3');
        await file.writeAsBytes(bytes);
        _tempFiles.add(file.path);

        await _originalAudioPlayer
            .setAudioSource(AudioSource.uri(Uri.file(file.path)));
        print('✅ Audio original chargé (Android fichier)');
      } else {
        final source = _BytesAudioSource(bytes);
        await _originalAudioPlayer.setAudioSource(source);
        print('✅ Audio original chargé (iOS mémoire)');
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

  Future<void> addAudioChunk(AudioChunk chunk) async {
    if (chunk.data.isEmpty || _isDisposed) return;

    try {
      final bytes = base64.decode(chunk.data);
      String? filePath;

      if (Platform.isAndroid) {
        await _initCacheIfNeeded();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final file =
            File('${_cacheDir!.path}/chunk_${chunk.sequence}_$timestamp.mp3');
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

      print('📦 Chunk #${chunk.sequence + 1} | '
          '${chunk.timestampStart.toStringAsFixed(2)}s - ${chunk.timestampEnd.toStringAsFixed(2)}s');

      if (_audioIndex.length == 1) {
        _hasFirstChunk = true;
        print('✅ Premier chunk prêt');
      }
    } catch (e) {
      print('❌ Erreur chunk: $e');
    }
  }

  Future<void> _playChunk(int index, {required bool videoPlaying}) async {
    if (index < 0 || index >= _audioIndex.length) return;

    final chunk = _audioIndex[index];

    try {
      await _translatedAudioPlayer.stop();

      if (Platform.isAndroid) {
        await _translatedAudioPlayer.setAudioSource(
          AudioSource.uri(Uri.file(chunk.filePath!)),
        );
      } else {
        await _translatedAudioPlayer.setAudioSource(
          _BytesAudioSource(chunk.bytes),
        );
      }

      await _translatedAudioPlayer.setVolume(_translatedVolume);

      if (videoPlaying) {
        await _translatedAudioPlayer.play();
      }

      _currentChunkIndex = index;

      print('🎧 Play chunk #${index + 1} '
          '(${chunk.timestampStart.toStringAsFixed(2)}s - ${chunk.timestampEnd.toStringAsFixed(2)}s)');
    } catch (e) {
      print('❌ Erreur _playChunk($index): $e');
    }
  }

  Future<void> startPlayback() async {
    if (_hasStarted) {
      print('⚠️ Déjà démarré');
      return;
    }
    if (!_hasFirstChunk || _audioIndex.isEmpty) {
      print('⚠️ Pas de chunk');
      return;
    }

    print('\n🎬 ========== DÉMARRAGE ==========');
    _hasStarted = true;

    try {
      await _translatedAudioPlayer.stop();
      if (_originalAudioLoaded) {
        await _originalAudioPlayer.seek(Duration.zero);
      }

      if (_isNativeVideoMode) {
        await nativeVideoController?.seekTo(Duration.zero);
      } else {
        _ytController?.seekTo(Duration.zero);
      }

      await _playChunk(0, videoPlaying: false);

      if (_originalAudioLoaded) {
        await _originalAudioPlayer.play();
      }

      if (_isNativeVideoMode) {
        await nativeVideoController?.play();
      } else {
        _ytController?.play();
      }

      await _translatedAudioPlayer.play();

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

    await _translatedAudioPlayer.play();

    if (_originalAudioLoaded) {
      await _originalAudioPlayer.play();
    }

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
    _lastVideoPlayingState = false;

    await _translatedAudioPlayer.pause();

    if (_originalAudioLoaded) {
      await _originalAudioPlayer.pause();
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
    print(
        '\n🎯 ===== SEEK CHUNK ${chunkIndex + 1}/${_audioIndex.length} =====');

    final wasPlaying = isPlaying;

    if (wasPlaying) {
      await pause();
      await Future.delayed(const Duration(milliseconds: 150));
    }

    final videoPos =
        Duration(milliseconds: (chunk.timestampStart * 1000).toInt());

    if (_isNativeVideoMode) {
      await nativeVideoController?.seekTo(videoPos);
    } else {
      _ytController?.seekTo(videoPos);
    }
    print('📹 Vidéo -> ${chunk.timestampStart.toStringAsFixed(2)}s');

    if (_originalAudioLoaded) {
      await _originalAudioPlayer.seek(
        Duration(milliseconds: (chunk.timestampStart * 1000).toInt()),
      );
      print('🎵 Audio original -> ${chunk.timestampStart.toStringAsFixed(2)}s');
    }

    await _playChunk(chunkIndex, videoPlaying: wasPlaying);

    if (wasPlaying) {
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
    if (!_translationComplete || _audioIndex.isEmpty) return;

    final t = position.inMilliseconds / 1000.0;

    int index = _audioIndex.lastIndexWhere(
      (c) => c.timestampStart <= t,
    );

    if (index < 0) index = 0;
    if (index >= _audioIndex.length) index = _audioIndex.length - 1;

    await _seekToChunk(index);
  }

  Future<void> goToStart() async {
    print('🏠 Retour au début');
    await _seekToChunk(0);
  }

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
          } catch (_) {}
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

    _cleanupTempFiles();

    super.dispose();
  }

  Future<void> _configureAudioSession() async {
    try {
      print('🔊 Configuration audio session...');

      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions:
            AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.moviePlayback,
        avAudioSessionRouteSharingPolicy:
            AVAudioSessionRouteSharingPolicy.defaultPolicy,
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
