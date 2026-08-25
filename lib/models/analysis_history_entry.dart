import 'video_metadata.dart';
import 'video_platform.dart';

class AnalysisHistoryEntry {
  const AnalysisHistoryEntry({
    required this.originalUrl,
    required this.title,
    required this.coverUrl,
    required this.platform,
    required this.analyzedAt,
  });

  final String originalUrl;
  final String title;
  final String coverUrl;
  final VideoPlatform platform;
  final DateTime analyzedAt;

  /// Compatibility view for existing UI call sites. Download qualities and
  /// signed CDN URLs are deliberately not retained in analysis history.
  VideoMetadata get metadata => VideoMetadata(
    id: '',
    originalUrl: originalUrl,
    title: title,
    author: '',
    coverUrl: coverUrl,
    platform: platform,
    qualities: const [],
  );

  factory AnalysisHistoryEntry.fromMetadata(
    VideoMetadata metadata, {
    required DateTime analyzedAt,
  }) => AnalysisHistoryEntry(
    originalUrl: metadata.originalUrl,
    title: metadata.title,
    coverUrl: metadata.coverUrl,
    platform: metadata.platform,
    analyzedAt: analyzedAt,
  );

  Map<String, dynamic> toJson() => {
    'url': originalUrl,
    'title': title,
    'coverUrl': coverUrl,
    'platform': platform.name,
    'analyzedAt': analyzedAt.toIso8601String(),
  };

  factory AnalysisHistoryEntry.fromJson(Map<String, dynamic> json) {
    final analyzedAt =
        DateTime.tryParse(json['analyzedAt']?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final legacy = json['metadata'];
    if (legacy is Map<String, dynamic>) {
      return AnalysisHistoryEntry.fromMetadata(
        VideoMetadata.fromJson(legacy),
        analyzedAt: analyzedAt,
      );
    }
    return AnalysisHistoryEntry(
      originalUrl: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString() ?? '',
      platform: VideoPlatform.values.firstWhere(
        (value) => value.name == json['platform'],
        orElse: () => VideoPlatform.generic,
      ),
      analyzedAt: analyzedAt,
    );
  }
}
