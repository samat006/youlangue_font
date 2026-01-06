// lib/presentation/screens/player_screen.dart

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../data/models/video_model.dart';
import '../../data/models/translation_model.dart';
import '../../data/services/websocket_service.dart';
import '../../data/services/synchronized_player_service.dart';
import '../widgets/transcript_view.dart';

class PlayerScreen extends StatefulWidget {
  final VideoModel video;
  final String targetLang;
  final String voiceType;

  const PlayerScreen({
    Key? key,
    required this.video,
    required this.targetLang,
    required this.voiceType,
  }) : super(key: key);

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  final WebSocketService _wsService = WebSocketService();
  late SynchronizedPlayerService _syncPlayer;
  
  String _status = 'Connexion...';
  String _voiceDetected = '';
  int _progress = 0;
  int _totalChunks = 0;
  List<AudioChunk> _transcripts = [];
  bool _isTranslating = false;
  bool _isDisposing = false;
  
  Timer? _uiTimer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  
  @override
  void initState() {
    super.initState();
    _initializeSyncPlayer();
    _connectAndStartTranslation();
    _startUIUpdates();
  }
  
  void _initializeSyncPlayer() {
    final videoId = YoutubePlayer.convertUrlToId(widget.video.url);
    _syncPlayer = SynchronizedPlayerService();
    _syncPlayer.initializeVideo(videoId!);
  }
  
  void _startUIUpdates() {
    _uiTimer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      if (!mounted || _isDisposing) {
        timer.cancel();
        return;
      }
      
      setState(() {
        _isPlaying = _syncPlayer.isPlaying;
        _currentPosition = _syncPlayer.position;
      });
    });
  }
  
  Future<void> _connectAndStartTranslation() async {
    setState(() {
      _status = 'Connexion au serveur...';
      _isTranslating = true;
    });
    
    try {
      await _wsService.connect();
      
      _wsService.stream?.listen(
        _handleWebSocketMessage,
        onError: (error) {
          if (!_isDisposing) {
            setState(() {
              _status = 'Erreur: $error';
              _isTranslating = false;
            });
          }
        },
        onDone: () {
          print('🔌 WebSocket fermé');
          if (!_isDisposing) {
            setState(() {
              _isTranslating = false;
            });
          }
        },
      );
      
      await Future.delayed(Duration(milliseconds: 500));
      
      _wsService.startTranslation(
        videoUrl: widget.video.url,
        targetLang: widget.targetLang,
        voicePreference: widget.voiceType,
      );
      
    } catch (e) {
      setState(() {
        _status = 'Erreur de connexion: $e';
        _isTranslating = false;
      });
    }
  }
  
  void _handleWebSocketMessage(dynamic message) {
    if (_isDisposing || !mounted) return;
    
    try {
      final data = json.decode(message);
      final type = data['type'] as String;
      
      switch (type) {
        case 'status':
          setState(() {
            _status = data['message'] ?? '';
          });
          break;
          
        case 'voice_detected':
          setState(() {
            _voiceDetected = data['voice_type'] ?? '';
            _status = '🎤 Voix détectée: $_voiceDetected';
          });
          break;
          
        case 'translation_ready':
          setState(() {
            _totalChunks = data['total_chunks'] ?? 0;
            _status = '⚡ Traduction en cours...';
          });
          break;
          
        case 'audio_chunk':
          final chunk = AudioChunk.fromJson(data);
          
          // ✅ Ajouter SANS await (la fonction n'est pas async)
          if (chunk.data.isNotEmpty) {
            _syncPlayer.addAudioChunk(chunk);
          }
          
          setState(() {
            _progress = chunk.progress;
            if (chunk.transcript.isNotEmpty) {
              _transcripts.add(chunk);
            }
          });
          break;
        
        case 'translation_complete':
          print('✅ Traduction terminée');
          _syncPlayer.markTranslationComplete();
          setState(() {
            _status = '✅ Terminé ! Vous pouvez maintenant avancer/reculer librement.';
            _isTranslating = false;
          });
          break;
          
        case 'error':
          setState(() {
            _status = 'Erreur: ${data['message']}';
            _isTranslating = false;
          });
          break;
      }
    } catch (e) {
      print('❌ Erreur parsing: $e');
    }
  }
  
  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              color: Colors.black87,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.video.title,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 4),
                        Text(
                          widget.video.channelTitle,
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Vidéo YouTube
            YoutubePlayer(
              controller: _syncPlayer.videoController,
              showVideoProgressIndicator: false,
              progressIndicatorColor: Color(0xFF667EEA),
              progressColors: ProgressBarColors(
                playedColor: Color(0xFF667EEA),
                handleColor: Color(0xFF764BA2),
              ),
            ),
            
            // Contrôles synchronisés
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                ),
              ),
              child: Column(
                children: [
                  // Position
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _formatDuration(_currentPosition),
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Contrôles principaux
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Reculer 10s
                      IconButton(
                        icon: Icon(Icons.replay_10, size: 36),
                        color: _syncPlayer.canSeek ? Colors.white : Colors.white30,
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekBackward(10)
                          : null,
                      ),
                      
                      SizedBox(width: 30),
                      
                      // Play/Pause
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black26,
                              blurRadius: 10,
                              offset: Offset(0, 5),
                            ),
                          ],
                        ),
                        child: IconButton(
                          icon: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            size: 54,
                          ),
                          color: Color(0xFF667EEA),
                          onPressed: () => _syncPlayer.playPause(),
                        ),
                      ),
                      
                      SizedBox(width: 30),
                      
                      // Avancer 10s
                      IconButton(
                        icon: Icon(Icons.forward_10, size: 36),
                        color: _syncPlayer.canSeek ? Colors.white : Colors.white30,
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekForward(10)
                          : null,
                      ),
                    ],
                  ),
                  
                  SizedBox(height: 20),
                  
                  // Contrôles secondaires
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.replay_5, color: Colors.white70),
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekBackward(5)
                          : null,
                        tooltip: '-5s',
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_previous, color: Colors.white70),
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekTo(Duration.zero)
                          : null,
                        tooltip: 'Début',
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next, color: Colors.white70),
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekForward(30)
                          : null,
                        tooltip: '+30s',
                      ),
                      IconButton(
                        icon: Icon(Icons.forward_5, color: Colors.white70),
                        onPressed: _syncPlayer.canSeek 
                          ? () => _syncPlayer.seekForward(5)
                          : null,
                        tooltip: '+5s',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Statut
            Container(
              padding: EdgeInsets.all(16),
              color: Color(0xFF2A2A2A),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (_isTranslating)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Color(0xFF667EEA)),
                          ),
                        ),
                      if (_isTranslating) SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status,
                          style: TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ),
                      if (_voiceDetected.isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Color(0xFF667EEA).withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _voiceDetected == 'male' ? '👨' :
                            _voiceDetected == 'female' ? '👩' : '👶',
                            style: TextStyle(fontSize: 16),
                          ),
                        ),
                    ],
                  ),
                  if (_totalChunks > 0) ...[
                    SizedBox(height: 12),
                    LinearProgressIndicator(
                      value: _progress / 100,
                      backgroundColor: Colors.grey[800],
                      valueColor: AlwaysStoppedAnimation(Color(0xFF667EEA)),
                    ),
                  ],
                ],
              ),
            ),
            
            // Transcriptions
            Expanded(
              child: Container(
                color: Color(0xFF1A1A1A),
                child: TranscriptView(transcripts: _transcripts),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    print('🧹 Nettoyage PlayerScreen');
    _isDisposing = true;
    _uiTimer?.cancel();
    _syncPlayer.dispose();
    
    Future.delayed(Duration(milliseconds: 500), () {
      _wsService.disconnect();
    });
    
    super.dispose();
  }
}