import 'dart:convert';
import 'dart:async';
import 'dart:ui';
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
  
  String _status = 'Initialisation...';
  String _voiceDetected = '';
  int _progress = 0;
  int _totalChunks = 0;
  List<AudioChunk> _transcripts = [];
  bool _isTranslating = false;
  bool _isDisposing = false;
  bool _waitingForFirstChunk = true;
  
  Timer? _uiTimer;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;

  // Couleurs du thème
  final Color primaryColor = const Color(0xFF6366F1); // Indigo moderne
  final Color accentColor = const Color(0xFFA855F7); // Violet
  final Color bgColor = const Color(0xFF0F172A); // Bleu nuit sombre

  @override
  void initState() {
    super.initState();
    _initializeSyncPlayer();
    _connectAndStartTranslation();
    _startUIUpdates();
  }

  // ... (Garder les méthodes d'initialisation identiques à ton code) ...
  void _initializeSyncPlayer() {
    final videoId = YoutubePlayer.convertUrlToId(widget.video.url);
    _syncPlayer = SynchronizedPlayerService();
    _syncPlayer.initializeVideo(videoId!);
  }

  void _startUIUpdates() {
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
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
    setState(() { _status = 'Connexion au serveur...'; _isTranslating = true; });
    try {
      await _wsService.connect();
      _wsService.stream?.listen(_handleWebSocketMessage);
      _wsService.startTranslation(
        videoUrl: widget.video.url,
        targetLang: widget.targetLang,
        voicePreference: widget.voiceType,
      );
    } catch (e) {
      setState(() { _status = 'Erreur de connexion'; _isTranslating = false; });
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (_isDisposing || !mounted) return;
    try {
      final data = json.decode(message);
      final type = data['type'] as String;
      switch (type) {
        case 'status': setState(() => _status = data['message'] ?? ''); break;
        case 'translation_ready':
          _syncPlayer.setTotalChunks(data['total_chunks'] ?? 0, (data['chunk_duration'] ?? 5.0).toDouble());
          setState(() => _totalChunks = data['total_chunks'] ?? 0);
          break;
        case 'audio_chunk':
          final chunk = AudioChunk.fromJson(data);
          if (chunk.data.isNotEmpty) {
            _syncPlayer.addAudioChunk(chunk);
            if (_waitingForFirstChunk && _syncPlayer.hasFirstChunk) {
              _waitingForFirstChunk = false;
              Future.delayed(const Duration(milliseconds: 800), () => _syncPlayer.startPlayback());
            }
          }
          setState(() {
            _progress = chunk.progress;
            if (chunk.transcript.isNotEmpty) _transcripts.add(chunk);
          });
          break;
        case 'translation_complete':
          _syncPlayer.markTranslationComplete();
          setState(() => _isTranslating = false);
          break;
      }
    } catch (e) { print('Error: $e'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          Column(
            children: [
              _buildHeader(),
              _buildVideoSection(),
              _buildUnifiedControls(),
              _buildStatusInterface(),
              Expanded(child: _buildTranscriptSection()),
            ],
          ),
          if (_waitingForFirstChunk) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 40, 16, 16),
      decoration: BoxDecoration(
        color: bgColor.withOpacity(0.8),
        border: Border(bottom: BorderSide(color: Colors.white10, width: 0.5)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.video.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(widget.video.channelTitle, style: TextStyle(color: Colors.blueGrey[300], fontSize: 12)),
              ],
            ),
          ),
          _buildLanguageBadge(),
        ],
      ),
    );
  }

  Widget _buildLanguageBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primaryColor.withOpacity(0.5)),
      ),
      child: Text(widget.targetLang.toUpperCase(), style: TextStyle(color: primaryColor, fontWeight: FontWeight.bold, fontSize: 10)),
    );
  }

  Widget _buildVideoSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 20, offset: const Offset(0, 10))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.center,
          children: [
            YoutubePlayer(controller: _syncPlayer.videoController, showVideoProgressIndicator: false),
            // Bloqueur d'interaction
            GestureDetector(
              onTap: () {},
              child: Container(color: Colors.transparent, height: 220),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnifiedControls() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [primaryColor.withOpacity(0.9), accentColor.withOpacity(0.9)],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(_currentPosition), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                child: Text('Chunk ${_syncPlayer.currentChunkIndex + 1}/${_totalChunks}', style: const TextStyle(color: Colors.white, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _controlButton(Icons.skip_previous_rounded, _syncPlayer.canNavigatePrevious, _syncPlayer.previousChunk),
              _playPauseButton(),
              _controlButton(Icons.skip_next_rounded, _syncPlayer.canNavigateNext, _syncPlayer.nextChunk),
            ],
          ),
        ],
      ),
    );
  }

  Widget _playPauseButton() {
    return GestureDetector(
      onTap: () => _syncPlayer.playPause(),
      child: Container(
        height: 65, width: 65,
        decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 15, offset: Offset(0, 5))]),
        child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 45, color: primaryColor),
      ),
    );
  }

  Widget _controlButton(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, size: 32),
      color: enabled ? Colors.white : Colors.white38,
      onPressed: enabled ? onTap : null,
    );
  }

  Widget _buildStatusInterface() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              if (_isTranslating) const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white54))),
              const SizedBox(width: 8),
              Expanded(child: Text(_status, style: const TextStyle(color: Colors.white70, fontSize: 12))),
              Text('$_progress%', style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(value: _progress / 100, minHeight: 4, backgroundColor: Colors.white10, valueColor: AlwaysStoppedAnimation(primaryColor)),
          ),
        ],
      ),
    );
  }

  Widget _buildTranscriptSection() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        borderRadius: BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30), topRight: Radius.circular(30)),
        child: TranscriptView(transcripts: _transcripts),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(primaryColor)),
              const SizedBox(height: 24),
              const Text('Préparation de la traduction...', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('Chunk 1 en cours de traitement', style: TextStyle(color: Colors.blueGrey[300], fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    return "${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}";
  }

  @override
  void dispose() {
    _isDisposing = true;
    _uiTimer?.cancel();
    _syncPlayer.dispose();
    _wsService.disconnect();
    super.dispose();
  }
}