// lib/data/models/translation_model.dart
// lib/data/models/translation_model.dart

class AudioChunk {
  final int sequence;
  final String data;
  final String transcript;
  final String translation;
  final int progress;
  final double timestampStart;  // ✅ NOUVEAU
  final double timestampEnd;    // ✅ NOUVEAU

  AudioChunk({
    required this.sequence,
    required this.data,
    required this.transcript,
    required this.translation,
    required this.progress,
    required this.timestampStart,
    required this.timestampEnd,
  });

  factory AudioChunk.fromJson(Map<String, dynamic> json) {
    return AudioChunk(
      sequence: json['sequence'] ?? 0,
      data: json['data'] ?? '',
      transcript: json['transcript'] ?? '',
      translation: json['translated'] ?? '',
      progress: json['progress'] ?? 0,
      timestampStart: (json['timestamp_start'] ?? 0.0).toDouble(),
      timestampEnd: (json['timestamp_end'] ?? 0.0).toDouble(),
    );
  }
}


class TranslationStatus {
  final String type;
  final String message;
  final int? totalChunks;
  final String? voiceType;
  final double? pitch;

  TranslationStatus({
    required this.type,
    required this.message,
    this.totalChunks,
    this.voiceType,
    this.pitch,
  });

  factory TranslationStatus.fromJson(Map<String, dynamic> json) {
    return TranslationStatus(
      type: json['type'] ?? '',
      message: json['message'] ?? '',
      totalChunks: json['total_chunks'],
      voiceType: json['voice_type'],
      pitch: json['pitch']?.toDouble(),
    );
  }
}