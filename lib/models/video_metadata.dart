import 'video_platform.dart';

class VideoQualityOption {
  final String id;
  final String label;
  final String quality; // e.g. "1080p", "720p", "480p", "Audio"
  final String format; // "mp4", "mp3", "m4a"
  final String downloadUrl;
  final int? sizeBytes;
  final bool isAudioOnly;
  final Map<String, String>? headers;

  const VideoQualityOption({
    required this.id,
    required this.label,
    required this.quality,
    required this.format,
    required this.downloadUrl,
    this.sizeBytes,
    this.isAudioOnly = false,
    this.headers,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'quality': quality,
        'format': format,
        'downloadUrl': downloadUrl,
        'sizeBytes': sizeBytes,
        'isAudioOnly': isAudioOnly,
        'headers': headers,
      };

  factory VideoQualityOption.fromJson(Map<String, dynamic> json) =>
      VideoQualityOption(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        quality: json['quality'] as String? ?? '',
        format: json['format'] as String? ?? 'mp4',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        sizeBytes: json['sizeBytes'] as int?,
        isAudioOnly: json['isAudioOnly'] as bool? ?? false,
        headers: (json['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
      );
}

class VideoMetadata {
  final String id;
  final String originalUrl;
  final String title;
  final String? description;
  final String author;
  final String? authorAvatar;
  final String coverUrl;
  final Duration? duration;
  final VideoPlatform platform;
  final List<VideoQualityOption> qualities;
  final int? viewCount;
  final int? likeCount;
  final int? commentCount;
  final int? shareCount;

  const VideoMetadata({
    required this.id,
    required this.originalUrl,
    required this.title,
    this.description,
    required this.author,
    this.authorAvatar,
    required this.coverUrl,
    this.duration,
    required this.platform,
    required this.qualities,
    this.viewCount,
    this.likeCount,
    this.commentCount,
    this.shareCount,
  });

  VideoQualityOption? get bestQuality {
    if (qualities.isEmpty) return null;
    final videoQualities = qualities.where((q) => !q.isAudioOnly).toList();
    if (videoQualities.isNotEmpty) return videoQualities.first;
    return qualities.first;
  }

  VideoQualityOption? get audioQuality {
    try {
      return qualities.firstWhere((q) => q.isAudioOnly);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'originalUrl': originalUrl,
        'title': title,
        'description': description,
        'author': author,
        'authorAvatar': authorAvatar,
        'coverUrl': coverUrl,
        'durationSeconds': duration?.inSeconds,
        'platform': platform.name,
        'qualities': qualities.map((q) => q.toJson()).toList(),
        'viewCount': viewCount,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'shareCount': shareCount,
      };

  factory VideoMetadata.fromJson(Map<String, dynamic> json) => VideoMetadata(
        id: json['id'] as String? ?? '',
        originalUrl: json['originalUrl'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled Video',
        description: json['description'] as String?,
        author: json['author'] as String? ?? 'Unknown',
        authorAvatar: json['authorAvatar'] as String?,
        coverUrl: json['coverUrl'] as String? ?? '',
        duration: json['durationSeconds'] != null
            ? Duration(seconds: json['durationSeconds'] as int)
            : null,
        platform: VideoPlatform.values.firstWhere(
          (p) => p.name == json['platform'],
          orElse: () => VideoPlatform.generic,
        ),
        qualities: (json['qualities'] as List<dynamic>?)
                ?.map((q) =>
                    VideoQualityOption.fromJson(q as Map<String, dynamic>))
                .toList() ??
            [],
        viewCount: json['viewCount'] as int?,
        likeCount: json['likeCount'] as int?,
        commentCount: json['commentCount'] as int?,
        shareCount: json['shareCount'] as int?,
      );
}
