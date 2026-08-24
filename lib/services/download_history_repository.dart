import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/download_task.dart';

abstract interface class DownloadHistoryRepository {
  Future<void> saveHistory(List<DownloadTask> tasks);
  Future<List<DownloadTask>> loadHistory();
  Future<List<DownloadTask>> loadDownloadReceipts();
  Future<void> saveDownloadReceipt(DownloadTask task);
  Future<void> saveDownloadReceipts(Iterable<DownloadTask> tasks);
  Future<void> removeDownloadReceipts(Set<String> ids);
}

class SharedPreferencesDownloadHistoryRepository
    implements DownloadHistoryRepository {
  const SharedPreferencesDownloadHistoryRepository();

  @override
  Future<void> saveHistory(List<DownloadTask> tasks) async {
    final encoded = jsonEncode(tasks.map((task) => task.toJson()).toList());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyDownloadHistory, encoded);
    } catch (_) {}
  }

  @override
  Future<List<DownloadTask>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decodeTasks(prefs.getString(AppConstants.keyDownloadHistory));
    } catch (_) {
      return [];
    }
  }

  @override
  Future<List<DownloadTask>> loadDownloadReceipts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return _decodeTasks(prefs.getString(AppConstants.keyDownloadReceipts));
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> saveDownloadReceipt(DownloadTask task) =>
      saveDownloadReceipts([task]);

  @override
  Future<void> saveDownloadReceipts(Iterable<DownloadTask> tasks) async {
    final snapshots = tasks
        .map((task) => DownloadTask.fromJson(task.toJson()))
        .toList();
    if (snapshots.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final receipts = await loadDownloadReceipts();
      final ids = snapshots.map((task) => task.id).toSet();
      receipts.removeWhere((entry) => ids.contains(entry.id));
      receipts.insertAll(0, snapshots);
      if (receipts.length > 500) receipts.removeRange(500, receipts.length);
      await prefs.setString(
        AppConstants.keyDownloadReceipts,
        jsonEncode(receipts.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {}
  }

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {
    if (ids.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final receipts = await loadDownloadReceipts()
        ..removeWhere((entry) => ids.contains(entry.id));
      await prefs.setString(
        AppConstants.keyDownloadReceipts,
        jsonEncode(receipts.map((entry) => entry.toJson()).toList()),
      );
    } catch (_) {}
  }

  List<DownloadTask> _decodeTasks(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    final values = jsonDecode(raw) as List<dynamic>;
    return values
        .map((item) => DownloadTask.fromJson(item as Map<String, dynamic>))
        .toList();
  }
}
