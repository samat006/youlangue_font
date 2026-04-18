// lib/data/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  StreamController<dynamic>? _streamController;
  Stream? stream;
  
  // Timeouts
  static const Duration connectionTimeout = Duration(seconds: 10);
  static const Duration messageTimeout = Duration(seconds: 180);
  
  Timer? _heartbeatTimer;
  DateTime? _lastMessageTime;
  
  // 🆕 Pour gérer la fermeture
  bool _isClosedByUser = false;
  StreamSubscription? _channelSubscription;

  Future<void> connect() async {
    try {
      print('🔌 Connexion WebSocket...');
      
      final clientId = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
      
      final uri = Uri.parse('ws://172.20.10.4:8000/ws/$clientId');
      
      final channel = WebSocketChannel.connect(uri);

      await channel.ready.timeout(
        connectionTimeout,
        onTimeout: () {
          throw TimeoutException('Délai de connexion dépassé (10s)');
        },
      );

      _channel = channel;
      _isClosedByUser = false;
      
      // 🆕 Créer un StreamController pour gérer les erreurs
      _streamController = StreamController.broadcast();
      
      // 🆕 Écouter le channel et gérer les erreurs
      _channelSubscription = _channel!.stream.listen(
        (message) {
          _lastMessageTime = DateTime.now();
          _streamController?.add(message);
        },
        onError: (error) {
          print('❌ Erreur WebSocket: $error');
          _streamController?.addError(error);
        },
        onDone: () {
          if (!_isClosedByUser) {
            print('⚠️ WebSocket fermé par le serveur');
            _streamController?.addError(Exception('WebSocket fermé par le serveur'));
          }
          print('🔌 WebSocket fermé');
        },
        cancelOnError: false, // 🔧 Important : ne pas fermer sur erreur
      );
      
      stream = _streamController!.stream;
      _lastMessageTime = DateTime.now();
      
      // Démarrer heartbeat
      _startHeartbeatCheck();
      
      print('✅ WebSocket connecté et prêt: $clientId');
    } catch (e) {
      print('❌ Erreur connexion WebSocket: $e');
      rethrow;
    }
  }

  void _startHeartbeatCheck() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_lastMessageTime != null) {
        final timeSinceLastMessage = DateTime.now().difference(_lastMessageTime!);
        
        if (timeSinceLastMessage > messageTimeout) {
          print('⚠️ Aucun message depuis ${timeSinceLastMessage.inSeconds}s - Déconnexion');
          disconnect();
          timer.cancel();
        } else {
          print('💓 Heartbeat check: ${timeSinceLastMessage.inSeconds}s depuis dernier message');
        }
      }
    });
  }

  void startTranslation({
    required String videoUrl,
    required String targetLang,
    required String voicePreference,
  }) {
    if (_channel == null) {
      print('❌ WebSocket non connecté');
      throw Exception('WebSocket non connecté');
    }

    try {
      final message = json.encode({
        'video_url': videoUrl,
        'target_lang': targetLang,
        'voice_preference': voicePreference,
        'action': 'start_translation',
      });

      _channel!.sink.add(message);
      _lastMessageTime = DateTime.now();
      print('📤 Message envoyé: $message');
    } catch (e) {
      print('❌ Erreur envoi message: $e');
      rethrow;
    }
  }

  void disconnect() {
    print('🔌 Déconnexion WebSocket demandée par l\'utilisateur');
    _isClosedByUser = true;
    _heartbeatTimer?.cancel();
    _channelSubscription?.cancel();
    _channel?.sink.close();
    _streamController?.close();
    
    _channel = null;
    _channelSubscription = null;
    _streamController = null;
    stream = null;
    _lastMessageTime = null;
  }
  
  // 🆕 Vérifier si connecté
  bool get isConnected => _channel != null && !_isClosedByUser;
}