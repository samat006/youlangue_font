// lib/data/services/audio_player_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';
import 'dart:async';

class PlayerState {
  final bool playing;
  final Duration position;
  final Duration duration;
  
  PlayerState({
    required this.playing,
    required this.position,
    required this.duration,
  });
}

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  final List<Uint8List> _chunks = [];
  final StreamController<PlayerState> _stateController = StreamController<PlayerState>.broadcast();
  
  bool _isBuilding = true; // En cours de réception des chunks
  ConcatenatingAudioSource? _playlist;
  
  AudioPlayerService() {
    _initializePlayer();
  }
  
  void _initializePlayer() {
    // Écouter les changements d'état
    _player.playerStateStream.listen((state) {
      _emitState();
    });
    
    _player.positionStream.listen((position) {
      _emitState();
    });
    
    _player.durationStream.listen((duration) {
      _emitState();
    });
  }
  
  void _emitState() {
    _stateController.add(PlayerState(
      playing: _player.playing,
      position: _player.position,
      duration: _player.duration ?? Duration.zero,
    ));
  }
  
  Stream<PlayerState> get playerStateStream => _stateController.stream;
  
  Future<void> addChunk(String base64Audio) async {
    if (base64Audio.isEmpty) return;
    
    try {
      final bytes = base64.decode(base64Audio);
      _chunks.add(bytes);
      
      print('📦 Chunk ajouté (total: ${_chunks.length})');
      
      // Construire la playlist si c'est le premier chunk
      if (_chunks.length == 4) {
        await _buildPlaylist();
      } else {
        // Ajouter à la playlist existante
        await _addToPlaylist(bytes);
      }
      
    } catch (e) {
      print('❌ Erreur ajout chunk: $e');
    }
  }
  
  Future<void> _buildPlaylist() async {
    try {
      _playlist = ConcatenatingAudioSource(
        children: [_BytesAudioSource(_chunks[0])],
      );
      
      await _player.setAudioSource(_playlist!);
      await _player.play();
      
      print('🎵 Playlist créée et lecture démarrée');
    } catch (e) {
      print('❌ Erreur build playlist: $e');
    }
  }
  
  Future<void> _addToPlaylist(Uint8List bytes) async {
    try {
      if (_playlist != null) {
        await _playlist!.add(_BytesAudioSource(bytes));
        print('➕ Chunk ajouté à la playlist');
      }
    } catch (e) {
      print('❌ Erreur ajout playlist: $e');
    }
  }
  
  Future<void> play() async {
    try {
      await _player.play();
      print('▶️ Play');
    } catch (e) {
      print('❌ Erreur play: $e');
    }
  }
  
  Future<void> pause() async {
    try {
      await _player.pause();
      print('⏸️ Pause');
    } catch (e) {
      print('❌ Erreur pause: $e');
    }
  }
  
  Future<void> stop() async {
    try {
      await _player.stop();
      await _player.seek(Duration.zero);
      print('⏹️ Stop');
    } catch (e) {
      print('❌ Erreur stop: $e');
    }
  }
  
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
      print('⏩ Seek à ${position.inSeconds}s');
    } catch (e) {
      print('❌ Erreur seek: $e');
    }
  }
  
  void dispose() {
    _player.dispose();
    _stateController.close();
    print('🗑️ AudioPlayerService disposed');
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