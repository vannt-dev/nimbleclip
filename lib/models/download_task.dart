import 'video_platform.dart';

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

class DownloadTask {
  final String id;
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String downloadUrl;
  final String originalUrl;
  final VideoPlatform platform;
  final String qualityLabel;
  final String format; // "mp4", "mp3"
  final bool isAudioOnly;
  final Map<String, String>? headers;

  DownloadStatus status;
  double progress; // 0.0 to 1.0
  int totalBytes;
  int receivedBytes;
  double downloadSpeed; // bytes per second
  String? filePath;
  String? errorMessage;
  DateTime createdAt;
  DateTime? completedAt;
  bool isSavedToGallery;

  DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.downloadUrl,
    required this.originalUrl,
    required this.platform,
    required this.qualityLabel,
    this.format = 'mp4',
    this.isAudioOnly = false,
    this.headers,
    this.status = DownloadStatus.queued,
    this.progress = 0.0,
    this.totalBytes = 0,
    this.receivedBytes = 0,
    this.downloadSpeed = 0.0,
    this.filePath,
    this.errorMessage,
    DateTime? createdAt,
    this.completedAt,
    this.isSavedToGallery = false,
  }) : createdAt = createdAt ?? DateTime.now();

  bool get isDone =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get isActive =>
      status == DownloadStatus.downloading ||
      status == DownloadStatus.queued;

  Map<String, dynamic> toJson() => {
        'id': id,
        'videoId': videoId,
        'title': title,
        'author': author,
        'thumbnailUrl': thumbnailUrl,
        'downloadUrl': downloadUrl,
        'originalUrl': originalUrl,
        'platform': platform.name,
        'qualityLabel': qualityLabel,
        'format': format,
        'isAudioOnly': isAudioOnly,
        'headers': headers,
        'status': status.name,
        'progress': progress,
        'totalBytes': totalBytes,
        'receivedBytes': receivedBytes,
        'filePath': filePath,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'completedAt': completedAt?.toIso8601String(),
        'isSavedToGallery': isSavedToGallery,
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String? ?? '',
        videoId: json['videoId'] as String? ?? '',
        title: json['title'] as String? ?? 'Untitled Video',
        author: json['author'] as String? ?? 'Unknown',
        thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
        downloadUrl: json['downloadUrl'] as String? ?? '',
        originalUrl: json['originalUrl'] as String? ?? '',
        platform: VideoPlatform.values.firstWhere(
          (p) => p.name == json['platform'],
          orElse: () => VideoPlatform.generic,
        ),
        qualityLabel: json['qualityLabel'] as String? ?? 'Default',
        format: json['format'] as String? ?? 'mp4',
        isAudioOnly: json['isAudioOnly'] as bool? ?? false,
        headers: (json['headers'] as Map<String, dynamic>?)?.map(
          (k, v) => MapEntry(k, v.toString()),
        ),
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == json['status'],
          orElse: () => DownloadStatus.completed,
        ),
        progress: (json['progress'] as num?)?.toDouble() ?? 1.0,
        totalBytes: json['totalBytes'] as int? ?? 0,
        receivedBytes: json['receivedBytes'] as int? ?? 0,
        filePath: json['filePath'] as String?,
        errorMessage: json['errorMessage'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
            : DateTime.now(),
        completedAt: json['completedAt'] != null
            ? DateTime.tryParse(json['completedAt'] as String)
            : null,
        isSavedToGallery: json['isSavedToGallery'] as bool? ?? false,
      );
}
