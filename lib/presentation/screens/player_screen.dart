// lib/presentation/screens/player_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import '../../data/models/video_model.dart';
import '../../data/models/translation_model.dart';
import '../../data/services/websocket_service.dart';
import '../../data/services/synchronized_player_service.dart';
import '../../data/services/ad_manager.dart';
import '../widgets/transcript_view.dart';
import 'package:video_player/video_player.dart';

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

class _PlayerScreenState extends State<PlayerScreen> with SingleTickerProviderStateMixin {
  final WebSocketService _wsService = WebSocketService();
  late SynchronizedPlayerService _syncPlayer;
  final AdManager _adManager = AdManager();

  String _status = 'Connexion NeuralNet...';
  double _progress = 0.0;
  List<AudioChunk> _transcripts = [];
  bool _isTranslating = true;
  bool _waitingForFirstChunk = true;
  bool _isPlaying = false;
  bool _isTranslationComplete = false;
  
  bool _isControlsExpanded = true;

  double _volTranslated = 1.0;
  double _volOriginal = 0.5;

  Timer? _uiTimer;
  Timer? _connectionTimeoutTimer;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final Color ytRed = const Color(0xFFFF0000);
  final Color ytBlack = const Color(0xFF0F0F0F);

  @override
  void initState() {
    super.initState();
    
    // Log device info
    print('📱 Device: ${Platform.operatingSystem}');
    print('📱 Video: ${widget.video.title}');
    
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _initializeSyncPlayer();
    _connectAndStartTranslation();
    _startUIUpdates();
    _startConnectionTimeout();
    
    _adManager.loadInterstitialAd();
    _adManager.loadRewardedAd();
  }

  void _startConnectionTimeout() {
    _connectionTimeoutTimer?.cancel();
    _connectionTimeoutTimer = Timer(const Duration(seconds: 120), () {
      if (_waitingForFirstChunk && mounted) {
        print('⏱️ TIMEOUT : Aucune donnée reçue après 120s');
        setState(() {
          _status = '❌ Connexion timeout';
          _waitingForFirstChunk = false;
        });
        
        _showErrorDialog(
          'Connexion timeout',
          'Impossible de se connecter au serveur. Vérifiez votre connexion internet et réessayez.',
        );
      }
    });
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: ytRed, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        content: Text(
          message,
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pop(context);
            },
            child: const Text('Retour', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _waitingForFirstChunk = true;
                _status = 'Reconnexion...';
                _progress = 0.0;
              });
              _connectAndStartTranslation();
              _startConnectionTimeout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: ytRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  void _initializeSyncPlayer() async {
    final isUploadedFile = widget.video.url.startsWith('uploaded://');
    
    if (isUploadedFile) {
      print('📁 Fichier uploadé avec vidéo');
      
      final filename = widget.video.url.replaceFirst('uploaded://', '');
      final videoUrl = 'http://172.20.10.4:8000/uploads/$filename';
      
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
      _wsService.stream?.listen(
        _handleWebSocketMessage,
        onError: (error) {
          print('❌ WebSocket error: $error');
          if (mounted) {
            _showErrorDialog(
              'Erreur de connexion',
              'La connexion au serveur a été perdue. Vérifiez votre connexion internet.',
            );
          }
        },
        onDone: () {
          print('🔌 WebSocket fermé');
          if (_waitingForFirstChunk && mounted) {
            _showErrorDialog(
              'Connexion perdue',
              'La connexion au serveur a été interrompue.',
            );
          }
        },
      );
      _wsService.startTranslation(
        videoUrl: widget.video.url,
        targetLang: widget.targetLang,
        voicePreference: widget.voiceType,
      );
    } catch (e) {
      print('❌ Erreur connexion: $e');
      if (mounted) {
        setState(() => _status = 'Erreur connexion');
        _showErrorDialog(
          'Erreur',
          'Impossible de se connecter au serveur. Vérifiez votre connexion internet.',
        );
      }
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    if (!mounted) return;
    
    // Annuler timeout quand message reçu
    if (_connectionTimeoutTimer != null && _connectionTimeoutTimer!.isActive) {
      _connectionTimeoutTimer!.cancel();
    }
    try {
      final data = json.decode(message);
      final type = data['type'];
      
      print('📨 WebSocket: $type');

      switch (type) {
        case 'status':
          setState(() => _status = data['message']);
          break;
         
        case 'heartbeat':
            print('💓 Heartbeat'); // Ne pas ignorer !
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
            _isTranslationComplete = true;
          });
          
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              _adManager.showInterstitialAd();
            }
          });
          break;
          
        case 'error':
          print('❌ Erreur serveur: ${data['message']}');
          setState(() {
            _status = 'Erreur: ${data['message']}';
            _waitingForFirstChunk = false;
          });
          
          _showErrorDialog(
            'Erreur serveur',
            data['message'] ?? 'Une erreur est survenue',
          );
          break;
      }
    } catch (e) { 
      print('❌ Erreur parsing: $e');
      
      setState(() {
        _status = 'Erreur de communication';
        _waitingForFirstChunk = false;
      });
      
      _showErrorDialog(
        'Erreur',
        'Impossible de communiquer avec le serveur.',
      );
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
            bottom: _isControlsExpanded ? 20 : -300,
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
    return AnimatedOpacity(
      opacity: _isControlsExpanded ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 50, 16, 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.7),
                  Colors.black.withOpacity(0.0),
                ],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Text(
                    widget.video.title.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        color: Colors.black.withOpacity(0.85),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: ytRed.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.translate,
                        size: 60,
                        color: ytRed,
                      ),
                    ),
                  );
                },
              ),
              
              const SizedBox(height: 30),
              
              if (_progress > 0)
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2,
                  ),
                ),
              
              const SizedBox(height: 20),
              
              Container(
                width: MediaQuery.of(context).size.width * 0.7,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: _progress > 0 ? _progress : 0.1,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [ytRed, Colors.orange],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: ytRed.withOpacity(0.5),
                          blurRadius: 10,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 30),
              
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Column(
                  children: [
                    Text(
                      _status,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    const SizedBox(height: 10),
                    
                    SizedBox(
                      width: 30,
                      height: 30,
                      child: CircularProgressIndicator(
                        color: ytRed,
                        strokeWidth: 3,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 20),
              
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _getLoadingTip(),
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 40),
              
              TextButton(
                onPressed: () {
                  _connectionTimeoutTimer?.cancel();
                  _wsService.disconnect();
                  Navigator.pop(context);
                },
                child: Text(
                  'Annuler',
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getLoadingTip() {
    final tips = [
      '💡 La traduction IA analyse la voix en temps réel',
      '🎯 L\'audio original et traduit seront synchronisés',
      '🌍 ${_getLanguageName(widget.targetLang)} détecté',
      '⚡ Traitement neuronal en cours...',
      '🎵 Synthèse vocale haute qualité',
      '🔊 Les volumes seront ajustables après le chargement',
      '⏱️ Préparation de la synchronisation parfaite...',
    ];
    
    if (_status.contains('Connexion')) return tips[3];
    if (_status.contains('Voix')) return tips[0];
    if (_status.contains('Audio')) return tips[4];
    if (_status.contains('chunk')) return tips[1];
    
    return tips[(_progress * tips.length).toInt() % tips.length];
  }

  String _getLanguageName(String code) {
    final languages = {
      'af': 'Afrikaans', 'am': 'አማርኛ', 'ar': 'العربية', 'az': 'Azərbaycan',
      'bg': 'Български', 'bn': 'বাংলা', 'bs': 'Bosanski', 'ca': 'Català',
      'cs': 'Čeština', 'cy': 'Cymraeg', 'da': 'Dansk', 'de': 'Deutsch',
      'el': 'Ελληνικά', 'en': 'English', 'es': 'Español', 'et': 'Eesti',
      'eu': 'Euskara', 'fa': 'فارسی', 'fi': 'Suomi', 'fil': 'Filipino',
      'fr': 'Français', 'ga': 'Gaeilge', 'gl': 'Galego', 'gu': 'ગુજરાતી',
      'he': 'עברית', 'hi': 'हिन्दी', 'hr': 'Hrvatski', 'hu': 'Magyar',
      'hy': 'Հայերեն', 'id': 'Indonesia', 'is': 'Íslenska', 'it': 'Italiano',
      'ja': '日本語', 'jv': 'Basa Jawa', 'ka': 'ქართული', 'kk': 'Қазақ',
      'km': 'ខ្មែរ', 'kn': 'ಕನ್ನಡ', 'ko': '한국어', 'lo': 'ລາວ',
      'lt': 'Lietuvių', 'lv': 'Latviešu', 'mk': 'Македонски', 'ml': 'മലയാളം',
      'mn': 'Монгол', 'mr': 'मराठी', 'ms': 'Melayu', 'mt': 'Malti',
      'my': 'မြန်မာ', 'nb': 'Norsk', 'ne': 'नेपाली', 'nl': 'Nederlands',
      'pl': 'Polski', 'ps': 'پښتو', 'pt': 'Português', 'ro': 'Română',
      'ru': 'Русский', 'si': 'සිංහල', 'sk': 'Slovenčina', 'sl': 'Slovenščina',
      'so': 'Soomaali', 'sq': 'Shqip', 'sr': 'Српски', 'su': 'Sunda',
      'sv': 'Svenska', 'sw': 'Kiswahili', 'ta': 'தமிழ்', 'te': 'తెలుగు',
      'th': 'ไทย', 'tr': 'Türkçe', 'uk': 'Українська', 'ur': 'اردو',
      'uz': 'Oʻzbek', 'vi': 'Tiếng Việt', 'wo': 'Wolof', 'zh': '中文',
      'zu': 'isiZulu',
    };
    return languages[code] ?? code.toUpperCase();
  }

  @override
  void dispose() {
    print('🗑️ Dispose PlayerScreen');
    _uiTimer?.cancel();
    _connectionTimeoutTimer?.cancel();
    _pulseController.dispose();
    _syncPlayer.dispose();
    _wsService.disconnect();
    super.dispose();
  }
}