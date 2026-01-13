// lib/presentation/screens/player_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../data/models/video_model.dart';
import '../../data/models/translation_model.dart';
import '../../data/services/websocket_service.dart';
import '../../data/services/synchronized_player_service.dart';
import '../widgets/transcript_view.dart';
import 'package:video_player/video_player.dart';
import '../../data/services/ad_manager.dart'; // ✅ CORRECTION du chemin

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
  final AdManager _adManager = AdManager(); // ✅ AJOUTER CETTE LIGNE

  String _status = 'Connexion NeuralNet...';
  double _progress = 0.0;
  List<AudioChunk> _transcripts = [];
  bool _isTranslating = true;
  bool _waitingForFirstChunk = true;
  bool _isPlaying = false;
  bool _isTranslationComplete = false; // ✅ AJOUTER
  
  bool _isControlsExpanded = true;

  double _volTranslated = 1.0;
  double _volOriginal = 0.5;

  Timer? _uiTimer;

  final Color ytRed = const Color(0xFFFF0000);
  final Color ytBlack = const Color(0xFF0F0F0F);

  @override
  void initState() {
    super.initState();
    _initializeSyncPlayer();
    _connectAndStartTranslation();
    _startUIUpdates();
    
    // ✅ PRÉCHARGER LES ADS
    _adManager.loadInterstitialAd();
    _adManager.loadRewardedAd();
  }

  void _initializeSyncPlayer() async {
    final isUploadedFile = widget.video.url.startsWith('uploaded://');
    
    if (isUploadedFile) {
      print('📁 Fichier uploadé avec vidéo');
      
      final filename = widget.video.url.replaceFirst('uploaded://', '');
      final videoUrl = 'http://youlangue-production.up.railway.app/uploads/$filename';
      
      print('🎬 URL vidéo: $videoUrl');
      
      _syncPlayer = SynchronizedPlayerService();
      await _syncPlayer.initializeNativeVideo(videoUrl);
      
    } else {
      final videoId = YoutubePlayer.convertUrlToId(widget.video.url);
      
      if (videoId == null) {
        print('❌ URL invalide');
        return;
      }
      
      print('🎬 Vidéo YouTube');
      _syncPlayer = SynchronizedPlayerService();
      _syncPlayer.initializeVideo(videoId);
    }
    
    Future.delayed(Duration(seconds: 1), () {
      _syncPlayer.setTranslatedVolume(_volTranslated);
      _syncPlayer.setOriginalVolume(_volOriginal);
    });
  }

  Widget _buildImmersiveVideo() {
    if (_syncPlayer.isNativeVideoMode && _syncPlayer.nativeVideoController != null) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.40,
        decoration: BoxDecoration(
          color: Colors.black,
          boxShadow: [
            BoxShadow(color: ytRed.withOpacity(0.1), blurRadius: 30, spreadRadius: 5),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: _syncPlayer.nativeVideoController!.value.aspectRatio,
                child: VideoPlayer(_syncPlayer.nativeVideoController!),
              ),
            ),
            Positioned.fill(
              child: AbsorbPointer(
                absorbing: true,
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      height: MediaQuery.of(context).size.height * 0.40,
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(color: ytRed.withOpacity(0.1), blurRadius: 30, spreadRadius: 5),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          YoutubePlayer(
            controller: _syncPlayer.videoController,
            showVideoProgressIndicator: false,
          ),
          Positioned.fill(
            child: AbsorbPointer(
              absorbing: true,
              child: Container(color: Colors.transparent),
            ),
          ),
        ],
      ),
    );
  }

  void _startUIUpdates() {
    _uiTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) return;
      setState(() {
        _isPlaying = _syncPlayer.isPlaying;
      });
    });
  }

  Future<void> _connectAndStartTranslation() async {
    try {
      await _wsService.connect();
      _wsService.stream?.listen(_handleWebSocketMessage);
      _wsService.startTranslation(
        videoUrl: widget.video.url,
        targetLang: widget.targetLang,
        voicePreference: widget.voiceType,
      );
    } catch (e) {
      setState(() => _status = 'Erreur uplink');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (!mounted) return;
    
    try {
      final data = json.decode(message);
      final type = data['type'];
      
      print('📨 WebSocket: $type');

      switch (type) {
        case 'status':
          setState(() => _status = data['message']);
          break;
         
        case 'voice_detected':
          final voiceType = data['voice_type'];
          print('🎤 Type de voix détecté: $voiceType');
          
          String emoji = '👤';
          if (voiceType == 'male') emoji = '👨';
          if (voiceType == 'female') emoji = '👩';
          if (voiceType == 'child') emoji = '👶';
          
          setState(() => _status = '$emoji Voix: $voiceType');
          break;
    
        case 'translation_ready':
          _syncPlayer.setTotalChunks(
            data['total_chunks'], 
            (data['chunk_duration'] ?? 10.0).toDouble()
          );
          break;
          
        case 'original_audio':
          print('🎵 Audio original reçu: ${data['data'].length} chars');
          _syncPlayer.loadOriginalAudio(data['data']);
          setState(() => _status = '🎵 Audio original chargé');
          break;
          
        case 'audio_chunk':
          final chunk = AudioChunk.fromJson(data);
          
          if (chunk.data.isNotEmpty) {
            _syncPlayer.addAudioChunk(chunk);
            
            if (_waitingForFirstChunk && _syncPlayer.hasFirstChunk) {
              print('✅ Premier chunk → Fermeture overlay');
              setState(() => _waitingForFirstChunk = false);
              
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  print('🎬 Démarrage lecture');
                  _syncPlayer.startPlayback();
                }
              });
            }
          }
          
          setState(() {
            _progress = (chunk.progress / 100);
            if (chunk.transcript.isNotEmpty) _transcripts.add(chunk);
          });
          break;
          
        case 'translation_complete':
          print('✅ Traduction complète');
          _syncPlayer.markTranslationComplete();
          setState(() {
            _status = "SYSTÈME PRÊT";
            _isTranslating = false;
            _isTranslationComplete = true; // ✅ AJOUTER
          });
          
          // ✅ AFFICHER INTERSTITIAL après 1 seconde
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _adManager.showInterstitialAd();
            }
          });
          break;
          
        case 'error':
          print('❌ Erreur serveur: ${data['message']}');
          setState(() => _status = 'Erreur: ${data['message']}');
          break;
      }
    } catch (e) { 
      print('❌ Erreur parsing: $e'); 
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ytBlack,
      body: Stack(
        children: [
          Column(
            children: [
              _buildImmersiveVideo(),
              Expanded(
                child: Container(
                  color: ytBlack,
                  child: Stack(
                    children: [
                      TranscriptView(transcripts: _transcripts),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          height: 150,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, ytBlack],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          Positioned(top: 0, left: 0, right: 0, child: _buildCyberHeader()),

          if (_waitingForFirstChunk) _buildLoadingOverlay(),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 400),
            curve: Curves.fastOutSlowIn,
            left: 15,
            right: 15,
            bottom: _isControlsExpanded ? 20 : -300, // ✅ Augmenté pour bouton rewarded
            child: _buildCollapsibleDock(),
          ),
          
          if (!_isControlsExpanded)
            Positioned(
              bottom: 30,
              right: 30,
              child: FloatingActionButton(
                backgroundColor: ytRed,
                child: const Icon(Icons.tune, color: Colors.white),
                onPressed: () => setState(() => _isControlsExpanded = true),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCollapsibleDock() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _isControlsExpanded = !_isControlsExpanded),
          child: Container(
            width: 60,
            height: 5,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        
        ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A).withOpacity(0.90),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _isControlsExpanded = false),
                    child: Icon(Icons.keyboard_arrow_down, color: Colors.white54, size: 30),
                  ),
                  
                  if (_progress > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation(ytRed),
                        minHeight: 2,
                      ),
                    ),

                  _buildVolumeMixer(),
                  
                  const SizedBox(height: 15),
                  Divider(color: Colors.white.withOpacity(0.1), height: 1),
                  const SizedBox(height: 15),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: () => _syncPlayer.playPause(),
                        child: Container(
                          height: 60, width: 60,
                          decoration: BoxDecoration(
                            color: ytRed,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: ytRed.withOpacity(0.5), blurRadius: 15, spreadRadius: 2),
                            ],
                          ),
                          child: Icon(
                            _isPlaying ? Icons.pause : Icons.play_arrow,
                            color: Colors.white, size: 35,
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 10),
                  Text(
                    "CHUNK ${_syncPlayer.currentChunkIndex + 1} / ${_syncPlayer.totalChunks}",
                    style: TextStyle(color: Colors.grey[600], fontSize: 10, letterSpacing: 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildVolumeMixer() {
    return Column(
      children: [
        // Volume traduit
        Row(
          children: [
            const Icon(Icons.record_voice_over, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Text(
              '${(_volTranslated * 100).toInt()}%',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: Colors.white,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _volTranslated,
                  onChanged: (val) {
                    setState(() => _volTranslated = val);
                    _syncPlayer.setTranslatedVolume(val);
                  },
                ),
              ),
            ),
          ],
        ),
        
        const SizedBox(height: 10),
        
        // Volume original
        Row(
          children: [
            Icon(Icons.volume_up, color: ytRed, size: 18),
            const SizedBox(width: 10),
            Text(
              '${(_volOriginal * 100).toInt()}%',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: ytRed,
                  inactiveTrackColor: Colors.white10,
                  thumbColor: ytRed,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: _volOriginal,
                  onChanged: (val) {
                    setState(() => _volOriginal = val);
                    _syncPlayer.setOriginalVolume(val);
                  },
                ),
              ),
            ),
          ],
        ),
        
        // ✅ BOUTON REWARDED (apparaît si volumes < 100%)
        if (_isTranslationComplete && (_volTranslated < 1.0 || _volOriginal < 1.0))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: ElevatedButton.icon(
              onPressed: _showRewardedForVolumeBoost,
              icon: const Icon(Icons.card_giftcard, size: 18),
              label: const Text('🎁 Volume Max'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ✅ MÉTHODE REWARDED
  Future<void> _showRewardedForVolumeBoost() async {
    if (!_adManager.isRewardedReady) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⏳ Chargement pub...'),
          duration: Duration(seconds: 2),
        ),
      );
      await _adManager.loadRewardedAd();
      return;
    }

    final rewarded = await _adManager.showRewardedAd();

    if (rewarded) {
      // ✅ RÉCOMPENSE : Volume max
      setState(() {
        _volTranslated = 1.0;
        _volOriginal = 1.0;
      });
      _syncPlayer.setTranslatedVolume(1.0);
      _syncPlayer.setOriginalVolume(1.0);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Volume max débloqué !'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildCyberHeader() {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
          color: Colors.black.withOpacity(0.4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              Expanded(
                child: Text(
                  widget.video.title.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        color: Colors.black54,
        child: Center(
          child: CircularProgressIndicator(color: ytRed),
        ),
      ),
    );
  }

  @override
  void dispose() {
    print('🗑️ Dispose PlayerScreen');
    _uiTimer?.cancel();
    _syncPlayer.dispose();
    _wsService.disconnect();
    super.dispose();
  }
}