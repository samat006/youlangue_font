// lib/data/services/websocket_service.dart

import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/translation_model.dart';
import '../../core/constants/api_constants.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  final String clientId = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
  
  Stream<dynamic>? get stream => _channel?.stream;
  
  Future<void> connect() async {
    try {
      final wsUrl = '${ApiConstants.wsUrl}/ws/$clientId';
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      print('✅ WebSocket connecté: $clientId');
    } catch (e) {
      print('❌ Erreur connexion WebSocket: $e');
      rethrow;
    }
  }
  
  void startTranslation({
    required String videoUrl,
    required String targetLang,
    String voicePreference = 'auto',
  }) {
    if (_channel == null) {
      throw Exception('WebSocket non connecté');
    }
    
    final message = json.encode({
      'action': 'start_translation',
      'video_url': videoUrl,
      'target_lang': targetLang,
      'voice_preference': voicePreference,
    });
    
    _channel!.sink.add(message);
    print('📤 Requête traduction envoyée');
  }
  
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    print('🔌 WebSocket déconnecté');
  }
}