import 'dart:io';

import 'package:nimble_clip/models/download_task.dart';
import 'package:nimble_clip/services/download_history_repository.dart';
import 'package:nimble_clip/services/media_file_actions.dart';
import 'package:nimble_clip/services/storage_service.dart';

/// The pieces of storage the provider touches, backed by real directories so
/// the rendered file can actually be asserted on.
class MemoryStorage
    implements StorageService, DownloadHistoryRepository, MediaFileActions {
  MemoryStorage(this.downloadDir);

  final Directory downloadDir;
  List<Map<String, dynamic>> history = [];
  List<Map<String, dynamic>> receipts = [];

  @override
  Future<String?> getDownloadDirectory() async => downloadDir.path;

  @override
  Future<List<DownloadTask>> loadHistory() async =>
      history.map(DownloadTask.fromJson).toList();

  @override
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots) async {
    history = snapshots.toList();
  }

  @override
  Future<List<DownloadTask>> loadDownloadReceipts() async =>
      receipts.map(DownloadTask.fromJson).toList();

  @override
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) async {
    receipts.removeWhere((entry) => entry['id'] == snapshot['id']);
    receipts.add(snapshot);
  }

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {
    for (final snapshot in snapshots) {
      await saveDownloadReceipt(snapshot);
    }
  }

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {
    receipts.removeWhere((entry) => ids.contains(entry['id']));
  }

  @override
  bool exists(String filePath) => File(filePath).existsSync();

  @override
  Future<void> delete(String filePath) async {
    final file = File(filePath);
    if (file.existsSync()) file.deleteSync();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
