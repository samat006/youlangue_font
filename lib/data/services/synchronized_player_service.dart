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
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  final List<IndexedAudioChunk> _audioIndex = [];
  ConcatenatingAudioSource? _playlist;
  
  bool _isSyncing = false;
  Timer? _syncTimer;
  bool _isDisposed = false;
  bool _translationComplete = false;
  
  bool _hasFirstChunk = false;
  bool _hasStarted = false;
  int _currentChunkIndex = 0;
  int _totalChunks = 0;
  double _chunkDuration = 5.0;
  
  bool _wasPlaying = false;
  double _lastVideoPosition = 0.0;
  
  bool get isPlaying => videoController.value.isPlaying;
  Duration get position => videoController.value.position;
  bool get canSeek => _translationComplete;
  bool get hasFirstChunk => _hasFirstChunk;
  int get currentChunkIndex => _currentChunkIndex;
  int get totalChunks => _totalChunks;
  int get availableChunks => _audioIndex.length;
  
  bool get canNavigateNext => _hasStarted && _currentChunkIndex < _audioIndex.length - 1;
  bool get canNavigatePrevious => _hasStarted && _currentChunkIndex > 0;
  
  void initializeVideo(String videoId) {
    videoController = YoutubePlayerController(
      initialVideoId: videoId,
      flags: YoutubePlayerFlags(
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
    
    _startAggressiveSync();
  }
  
  void setTotalChunks(int total, double chunkDuration) {
    _totalChunks = total;
    _chunkDuration = chunkDuration;
    print('📊 Total: $_totalChunks chunks (${chunkDuration}s/chunk)');
  }
  
  void _startAggressiveSync() {
    _syncTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (_isDisposed) {
        timer.cancel();
        return;
      }
      
      // ✅ RESPECTER _isSyncing
      if (_isSyncing) return;
      
      if (!_hasStarted) return;
      
      _checkPlayPauseState();
      _checkPositionJump();
      _checkDrift();
      _updateCurrentChunk();
    });
  }
  
  void _checkPlayPauseState() {
    final isNowPlaying = videoController.value.isPlaying;
    final audioIsPlaying = _audioPlayer.playing;
    
    if (isNowPlaying != _wasPlaying) {
      if (isNowPlaying && !audioIsPlaying) {
        _audioPlayer.play();
      } else if (!isNowPlaying && audioIsPlaying) {
        _audioPlayer.pause();
      }
      _wasPlaying = isNowPlaying;
    }
  }
  
  void _checkPositionJump() {
    final currentVideoPos = videoController.value.position.inSeconds.toDouble();
    final positionDiff = (currentVideoPos - _lastVideoPosition).abs();
    
    if (positionDiff > 2.0) {
      print('🎯 Jump détecté: ${_lastVideoPosition.toStringAsFixed(1)}s → ${currentVideoPos.toStringAsFixed(1)}s');
      _syncAudioToVideoPosition(currentVideoPos);
    }
    
    _lastVideoPosition = currentVideoPos;
  }
  
  void _checkDrift() {
    if (!videoController.value.isPlaying) return;
    if (_playlist == null) return;
    
    final videoPos = videoController.value.position.inSeconds.toDouble();
    final audioPos = _audioPlayer.position.inSeconds.toDouble();
    final drift = (videoPos - audioPos).abs();
    
    if (drift > 1.5) {
      print('⚠️ Drift: ${drift.toStringAsFixed(1)}s');
      _syncAudioToVideoPosition(videoPos);
    }
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
  
 // lib/data/services/synchronized_player_service.dart

// MODIFIER addAudioChunk pour voir les timestamps

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
    
    // ✅ AFFICHER LES TIMESTAMPS
    print('📦 Chunk #${chunk.sequence + 1} | START: ${chunk.timestampStart.toStringAsFixed(1)}s | END: ${chunk.timestampEnd.toStringAsFixed(1)}s | Total: ${_audioIndex.length}');
    
    if (_audioIndex.length == 1) {
      await _buildAudioPlaylist();
      _hasFirstChunk = true;
      print('✅ Premier chunk prêt');
    } else if (_playlist != null) {
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
      await _audioPlayer.setAudioSource(_playlist!);
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
    print('▶️ Vidéo');
    
    await Future.delayed(Duration(milliseconds: 200));
    
    await _audioPlayer.play();
    print('▶️ Audio');
    
    _wasPlaying = true;
    _isSyncing = false;
  }
  
  void markTranslationComplete() {
    _translationComplete = true;
    print('✅ Traduction OK');
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
  if (chunkIndex < 0 || chunkIndex >= _audioIndex.length) {
    print('⚠️ Index invalide: $chunkIndex / ${_audioIndex.length}');
    return;
  }
  
  final chunk = _audioIndex[chunkIndex];
  
  // ✅ AFFICHER LE CHUNK QU'ON RÉCUPÈRE
  print('\n🎯 === SEEK CHUNK ${chunkIndex + 1}/${_audioIndex.length} ===');
  print('📦 Chunk récupéré: START=${chunk.timestampStart.toStringAsFixed(1)}s END=${chunk.timestampEnd.toStringAsFixed(1)}s');
  
  // 1. BLOQUER SYNC
  _isSyncing = true;
  print('🔒 Sync OFF');
  
  // 2. ÉTAT
  final wasPlayingBefore = videoController.value.isPlaying;
  
  // 3. PAUSE
  if (wasPlayingBefore) {
    videoController.pause();
    await _audioPlayer.pause();
    print('⏸️ Pause');
    await Future.delayed(Duration(milliseconds: 150));
  }
  
  // 4. SEEK VIDÉO
  final targetPos = Duration(milliseconds: (chunk.timestampStart * 1000).toInt());
  print('🎬 Calcul position: ${chunk.timestampStart}s * 1000 = ${chunk.timestampStart * 1000}ms');
  videoController.seekTo(targetPos);
  print('📹 Vidéo seek → ${chunk.timestampStart.toStringAsFixed(1)}s');
  
  // 5. ATTENDRE
  await Future.delayed(Duration(milliseconds: 500));
  
  // 6. UPDATE POSITION
  _lastVideoPosition = chunk.timestampStart;
  _currentChunkIndex = chunkIndex;
  print('📍 lastVideoPosition = ${_lastVideoPosition.toStringAsFixed(1)}s');
  print('📍 currentChunkIndex = ${_currentChunkIndex + 1}');
  
  // 7. SYNC AUDIO
  print('🎵 Sync audio vers ${chunk.timestampStart.toStringAsFixed(1)}s...');
  await _syncAudioToVideoPosition(chunk.timestampStart);
  
  // 8. ATTENDRE
  await Future.delayed(Duration(milliseconds: 300));
  
  // 9. REPRENDRE
  if (wasPlayingBefore) {
    videoController.play();
    await Future.delayed(Duration(milliseconds: 150));
    await _audioPlayer.play();
    print('▶️ Play');
  }
  
  // 10. ATTENDRE
  await Future.delayed(Duration(milliseconds: 300));
  
  // 11. DÉBLOQUER
  _isSyncing = false;
  print('🔓 Sync ON');
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
  if (_audioIndex.isEmpty || _playlist == null) {
    print('⚠️ Pas de chunks ou playlist');
    return;
  }
  
  print('🔍 Recherche chunk pour position: ${targetSeconds.toStringAsFixed(1)}s');
  print('🔍 Chunks disponibles: ${_audioIndex.length}');
  
  int targetChunkIndex = -1;
  double offsetInTargetChunk = 0.0;
  
  // ✅ AFFICHER TOUS LES CHUNKS
  for (int i = 0; i < _audioIndex.length; i++) {
    final c = _audioIndex[i];
    print('   Chunk $i: ${c.timestampStart.toStringAsFixed(1)}s - ${c.timestampEnd.toStringAsFixed(1)}s');
  }
  
  // Chercher le chunk correspondant
  for (int i = 0; i < _audioIndex.length; i++) {
    final chunk = _audioIndex[i];
    
    if (targetSeconds >= chunk.timestampStart && targetSeconds < chunk.timestampEnd) {
      targetChunkIndex = i;
      offsetInTargetChunk = targetSeconds - chunk.timestampStart;
      print('✅ Trouvé: Chunk $i (offset: ${offsetInTargetChunk.toStringAsFixed(1)}s)');
      break;
    }
  }
  
  // Si pas trouvé, prendre le plus proche
  if (targetChunkIndex == -1) {
    print('⚠️ Pas de match exact, recherche du plus proche...');
    double minDistance = double.infinity;
    for (int i = 0; i < _audioIndex.length; i++) {
      final chunk = _audioIndex[i];
      final distance = (chunk.timestampStart - targetSeconds).abs();
      print('   Chunk $i: distance = ${distance.toStringAsFixed(1)}s');
      if (distance < minDistance) {
        minDistance = distance;
        targetChunkIndex = i;
        offsetInTargetChunk = 0.0;
      }
    }
    print('✅ Plus proche: Chunk $targetChunkIndex (distance: ${minDistance.toStringAsFixed(1)}s)');
  }
  
  if (targetChunkIndex >= 0) {
    // Calculer position audio totale
    double totalAudioPosition = 0.0;
    
    print('🧮 Calcul position audio:');
    for (int i = 0; i < targetChunkIndex; i++) {
      final chunk = _audioIndex[i];
      final duration = chunk.timestampEnd - chunk.timestampStart;
      totalAudioPosition += duration;
      print('   + Chunk $i: ${duration.toStringAsFixed(1)}s → Total: ${totalAudioPosition.toStringAsFixed(1)}s');
    }
    
    totalAudioPosition += offsetInTargetChunk;
    print('   + Offset: ${offsetInTargetChunk.toStringAsFixed(1)}s → Total FINAL: ${totalAudioPosition.toStringAsFixed(1)}s');
    
    print('🎵 Audio seek → ${totalAudioPosition.toStringAsFixed(1)}s');
    
    try {
      await _audioPlayer.seek(Duration(milliseconds: (totalAudioPosition * 1000).toInt()));
      print('✅ Audio positionné');
    } catch (e) {
      print('❌ Erreur audio seek: $e');
    }
  } else {
    print('❌ Aucun chunk trouvé !');
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
    
    await _audioPlayer.play();
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
    await _audioPlayer.pause();
    
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