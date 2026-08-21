import 'dart:async';

import 'package:flutter/foundation.dart';

import 'video_platform.dart';
import 'video_metadata.dart' show MediaKind;

enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  handedOff,
  failed,
  cancelled,
}

class DownloadTask extends ChangeNotifier {
  static const _progressNotificationInterval = Duration(milliseconds: 100);

  final String id;
  final String videoId;
  final String title;
  final String author;
  final String thumbnailUrl;
  final String downloadUrl;
  final String originalUrl;
  final VideoPlatform platform;
  final String sourceOptionId;
  final String qualityLabel;
  final String format; // "mp4", "mp3"
  final MediaKind kind;
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
  Timer? _progressTimer;
  DateTime _lastProgressNotification = DateTime.fromMillisecondsSinceEpoch(0);
  bool _disposed = false;

  DownloadTask({
    required this.id,
    required this.videoId,
    required this.title,
    required this.author,
    required this.thumbnailUrl,
    required this.downloadUrl,
    required this.originalUrl,
    required this.platform,
    this.sourceOptionId = '',
    required this.qualityLabel,
    this.format = 'mp4',
    this.kind = MediaKind.video,
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

  bool get isAudioOnly => kind == MediaKind.audio;
  bool get isImage => kind == MediaKind.image;

  /// Notifies only widgets rendering this task. Collection-level changes
  /// (insert/remove/status buckets) remain the provider's responsibility.
  void notifyProgressChanged() {
    if (_disposed) return;
    final elapsed = DateTime.now().difference(_lastProgressNotification);
    if (elapsed >= _progressNotificationInterval) {
      _lastProgressNotification = DateTime.now();
      notifyListeners();
      return;
    }
    _progressTimer ??= Timer(_progressNotificationInterval - elapsed, () {
      _progressTimer = null;
      if (_disposed) return;
      _lastProgressNotification = DateTime.now();
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _progressTimer?.cancel();
    super.dispose();
  }

  bool get isDone =>
      status == DownloadStatus.completed ||
      status == DownloadStatus.handedOff ||
      status == DownloadStatus.failed ||
      status == DownloadStatus.cancelled;

  bool get isActive =>
      status == DownloadStatus.downloading || status == DownloadStatus.queued;

  /// Statuses that only make sense while a download is in flight.
  static const Set<DownloadStatus> transientStatuses = {
    DownloadStatus.queued,
    DownloadStatus.downloading,
    DownloadStatus.paused,
  };

  static DownloadStatus _restoreStatus(String? name) {
    final status = DownloadStatus.values.firstWhere(
      (s) => s.name == name,
      orElse: () => DownloadStatus.completed,
    );
    return transientStatuses.contains(status) ? DownloadStatus.failed : status;
  }

  /// Copy carrying a fresh download URL and headers, used when a retry has to
  /// re-extract because the persisted URL's signature has expired.
  DownloadTask withRefreshedSource({
    required String downloadUrl,
    Map<String, String>? headers,
  }) {
    return DownloadTask(
      id: id,
      videoId: videoId,
      title: title,
      author: author,
      thumbnailUrl: thumbnailUrl,
      downloadUrl: downloadUrl,
      originalUrl: originalUrl,
      platform: platform,
      sourceOptionId: sourceOptionId,
      qualityLabel: qualityLabel,
      format: format,
      kind: kind,
      headers: headers ?? this.headers,
      status: DownloadStatus.queued,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoId': videoId,
    'title': title,
    'author': author,
    'thumbnailUrl': thumbnailUrl,
    'downloadUrl': downloadUrl,
    'originalUrl': originalUrl,
    'platform': platform.name,
    'sourceOptionId': sourceOptionId,
    'qualityLabel': qualityLabel,
    'format': format,
    'kind': kind.name,
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
    sourceOptionId: json['sourceOptionId'] as String? ?? '',
    qualityLabel: json['qualityLabel'] as String? ?? 'Default',
    format: json['format'] as String? ?? 'mp4',
    kind: MediaKind.values.firstWhere(
      (kind) => kind.name == json['kind'],
      orElse: () => json['isImage'] == true
          ? MediaKind.image
          : json['isAudioOnly'] == true
          ? MediaKind.audio
          : MediaKind.video,
    ),
    headers: (json['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString()),
    ),
    // A task persisted as queued/downloading/paused belongs to a process
    // that no longer exists — nothing resumes it, so restoring it as-is
    // would leave it pinned to the "active" list forever. Mark it failed so
    // the user can retry it deliberately.
    status: _restoreStatus(json['status']?.toString()),
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
