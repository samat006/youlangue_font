// lib/data/services/youtube_service.dart

import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/video_model.dart';
import '../../core/constants/api_constants.dart';

class YouTubeService {
  Future<List<VideoModel>> searchVideos(String query) async {
    try {
      final url = Uri.parse(
        '${ApiConstants.youtubeSearchUrl}'
        '?part=snippet'
        '&q=${Uri.encodeComponent(query)}'
        '&type=video'
        '&maxResults=20'
        '&key=${ApiConstants.youtubeApiKey}'
      );

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final items = data['items'] as List;
        
        return items
          .map((item) => VideoModel.fromYouTubeJson(item))
          .toList();
      } else {
        throw Exception('Erreur recherche YouTube: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Erreur YouTube: $e');
      rethrow;
    }
  }
}