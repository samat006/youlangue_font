// lib/core/constants/api_constants.dart
import 'package:flutter/material.dart'; 
class ApiConstants {
  // Backend
  static const String baseUrl = 'http://172.20.10.4:8000';
  static const String wsUrl = 'ws://172.20.10.4:8000';
  
  // YouTube Data API v3 (gratuit : 10K requêtes/jour)
  static const String youtubeApiKey = 'AIzaSyBTfCSYdzv0Tgylcve0oYalyLpf0XlvIro';
  static const String youtubeSearchUrl = 
    'https://www.googleapis.com/youtube/v3/search';
  
  // Endpoints
  static const String wsEndpoint = '/ws';
  static const String videoInfoEndpoint = '/video-info';
}

class AppStrings {
  static const String appName = 'Video Translator';
  static const String searchHint = 'Rechercher une vidéo YouTube...';
  static const String selectLanguage = 'Langue cible';
  static const String selectVoice = 'Type de voix';
  static const String startTranslation = 'Démarrer la traduction';
}

class AppColors {
  static const primary = Color(0xFF667EEA);
  static const secondary = Color(0xFF764BA2);
  static const background = Color(0xFFF5F5F5);
  static const cardBackground = Color(0xFFFFFFFF);
  static const textPrimary = Color(0xFF333333);
  static const textSecondary = Color(0xFF888888);
}