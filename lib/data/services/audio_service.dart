// lib/data/services/audio_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:just_audio/just_audio.dart';

class AudioService {
  final AudioPlayer _player = AudioPlayer();
  final List<Uint8List> _audioQueue = [];
  bool _isPlaying = false;
  bool _isStopped = false; // ✅ NOUVEAU
  
  Future<void> addChunk(String base64Audio) async {
    if (base64Audio.isEmpty || _isStopped) return;
    
    try {
      final bytes = base64.decode(base64Audio);
      _audioQueue.add(bytes);
      
      // ✅ Démarrer dès le 1er chunk
      if (!_isPlaying && _audioQueue.length >= 1 && !_isStopped) {
        await _playNextChunk();
      }
    } catch (e) {
      print('❌ Erreur ajout chunk: $e');
    }
  }
  
  Future<void> _playNextChunk() async {
    if (_audioQueue.isEmpty || _isStopped) {
      _isPlaying = false;
      return;
    }
    
    _isPlaying = true;
    final chunk = _audioQueue.removeAt(0);
    
    try {
      await _player.setAudioSource(_BytesAudioSource(chunk));
      await _player.play();
      
      await _player.processingStateStream
        .firstWhere((state) => state == ProcessingState.completed);
      
      // ✅ Vérifier si pas stoppé avant de continuer
      if (!_isStopped) {
        await _playNextChunk();
      }
    } catch (e) {
      print('❌ Erreur lecture: $e');
      _isPlaying = false;
    }
  }
  
  int get queueSize => _audioQueue.length;
  
  Future<void> stop() async {
    print('🛑 Arrêt audio service');
    _isStopped = true;
    
    try {
      await _player.stop();
    } catch (e) {
      print('⚠️ Erreur stop: $e');
    }
    
    _audioQueue.clear();
    _isPlaying = false;
  }
  
  void dispose() {
    print('🗑️ Dispose audio service');
    _isStopped = true;
    _player.dispose();
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