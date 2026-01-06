// lib/data/models/video_model.dart

class VideoModel {
  final String id;
  final String title;
  final String thumbnail;
  final String channelTitle;
  final String duration;
  final String url;

  VideoModel({
    required this.id,
    required this.title,
    required this.thumbnail,
    required this.channelTitle,
    required this.duration,
    required this.url,
  });

  factory VideoModel.fromYouTubeJson(Map<String, dynamic> json) {
    return VideoModel(
      id: json['id']['videoId'] ?? '',
      title: json['snippet']['title'] ?? '',
      thumbnail: json['snippet']['thumbnails']['high']['url'] ?? '',
      channelTitle: json['snippet']['channelTitle'] ?? '',
      duration: '', // Nécessite un appel API supplémentaire
      url: 'https://www.youtube.com/watch?v=${json['id']['videoId']}',
    );
  }
}