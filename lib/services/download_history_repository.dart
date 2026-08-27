import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../models/download_task.dart';

/// Persistence for download history and completion receipts.
///
/// The save methods take already-serialized records rather than live
/// [DownloadTask] objects. A task is a `ChangeNotifier` whose fields keep
/// changing while a write is in flight, so the caller has to freeze it anyway;
/// handing over the map it would be encoded into skips a whole round of
/// `fromJson(toJson())` clones per save.
abstract interface class DownloadHistoryRepository {
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots);
  Future<List<DownloadTask>> loadHistory();
  Future<List<DownloadTask>> loadDownloadReceipts();
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot);
  Future<void> saveDownloadReceipts(Iterable<Map<String, dynamic>> snapshots);
  Future<void> removeDownloadReceipts(Set<String> ids);
}

class SharedPreferencesDownloadHistoryRepository
    implements DownloadHistoryRepository {
  SharedPreferencesDownloadHistoryRepository();

  static const int _maximumReceipts = 500;

  /// Receipts held as the records they are written as.
  ///
  /// Every completed download used to re-read the whole store from
  /// preferences, rebuild up to 500 `DownloadTask` objects from it and encode
  /// them all again. This repository is the only writer, so the list it last
  /// wrote is authoritative and re-reading it bought nothing.
  List<Map<String, dynamic>>? _receiptCache;

  @override
  Future<void> saveHistory(List<Map<String, dynamic>> snapshots) async {
    final encoded = jsonEncode(snapshots);
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
    final cached = await _receipts();
    return cached
        .map((entry) => DownloadTask.fromJson(entry))
        .toList(growable: false);
  }

  @override
  Future<void> saveDownloadReceipt(Map<String, dynamic> snapshot) =>
      saveDownloadReceipts([snapshot]);

  @override
  Future<void> saveDownloadReceipts(
    Iterable<Map<String, dynamic>> snapshots,
  ) async {
    final incoming = snapshots.toList(growable: false);
    if (incoming.isEmpty) return;
    final receipts = await _receipts();
    final ids = incoming.map((entry) => entry['id']).toSet();
    receipts
      ..removeWhere((entry) => ids.contains(entry['id']))
      ..insertAll(0, incoming);
    if (receipts.length > _maximumReceipts) {
      receipts.removeRange(_maximumReceipts, receipts.length);
    }
    await _writeReceipts(receipts);
  }

  @override
  Future<void> removeDownloadReceipts(Set<String> ids) async {
    if (ids.isEmpty) return;
    final receipts = await _receipts()
      ..removeWhere((entry) => ids.contains(entry['id']));
    await _writeReceipts(receipts);
  }

  /// The receipt records, read from preferences once per process.
  Future<List<Map<String, dynamic>>> _receipts() async {
    final cached = _receiptCache;
    if (cached != null) return cached;
    List<Map<String, dynamic>> loaded;
    try {
      final prefs = await SharedPreferences.getInstance();
      loaded = _decodeRecords(
        prefs.getString(AppConstants.keyDownloadReceipts),
      );
    } catch (_) {
      loaded = [];
    }
    // Another call may have populated the cache while this one awaited.
    return _receiptCache ??= loaded;
  }

  Future<void> _writeReceipts(List<Map<String, dynamic>> receipts) async {
    _receiptCache = receipts;
    final encoded = jsonEncode(receipts);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyDownloadReceipts, encoded);
    } catch (_) {}
  }

  List<DownloadTask> _decodeTasks(String? raw) {
    return _decodeRecords(
      raw,
    ).map(DownloadTask.fromJson).toList(growable: false);
  }

  List<Map<String, dynamic>> _decodeRecords(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      return values.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }
}
