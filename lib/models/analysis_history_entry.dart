import 'video_metadata.dart';

class AnalysisHistoryEntry {
  const AnalysisHistoryEntry({
    required this.metadata,
    required this.analyzedAt,
  });

  final VideoMetadata metadata;
  final DateTime analyzedAt;

  Map<String, dynamic> toJson() => {
    'metadata': metadata.toJson(),
    'analyzedAt': analyzedAt.toIso8601String(),
  };

  factory AnalysisHistoryEntry.fromJson(Map<String, dynamic> json) =>
      AnalysisHistoryEntry(
        metadata: VideoMetadata.fromJson(
          json['metadata'] as Map<String, dynamic>? ?? const {},
        ),
        analyzedAt:
            DateTime.tryParse(json['analyzedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
}
