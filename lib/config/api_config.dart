import 'dart:io';

class ApiConfig {
  // ✅ URL adaptée à la plateforme
  static String get baseUrl {
    if (Platform.isAndroid) {
      // Émulateur Android : 10.0.2.2
      return 'http://10.0.2.2:8000';
    } else if (Platform.isIOS) {
      // iOS Simulator : localhost
      return 'http://localhost:8000';
    } else {
      // Device réel : IP de ton ordinateur
      // À remplacer par l'IP locale de ton Mac
      return 'http://172.20.10.4:8000';  
    }
  }
  
  static String get wsUrl {
    final base = baseUrl.replaceFirst('http', 'ws');
    return '$base/ws';
  }
}