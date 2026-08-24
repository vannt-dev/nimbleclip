import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/platform_file.dart';
import '../models/download_task.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// Gets the local storage directory path for saved videos (null on Web)
  Future<String?> getDownloadDirectory() async {
    return await PlatformFileHelper.getDownloadDirectoryPath();
  }

  /// Request permissions for saving videos
  Future<bool> requestStoragePermissions() async {
    return await PlatformFileHelper.requestStoragePermissions();
  }

  /// Saves video or audio to device gallery
  Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async {
    return await PlatformFileHelper.saveToGallery(
      filePath,
      isAudio: isAudio,
      isImage: isImage,
    );
  }

  Future<bool?> galleryFileExists(String filePath, {required bool isImage}) =>
      PlatformFileHelper.galleryFileExists(filePath, isImage: isImage);

  Future<String?> galleryFileUri(String filePath, {required bool isImage}) =>
      PlatformFileHelper.galleryFileUri(filePath, isImage: isImage);

  /// Persists task list to SharedPreferences
  Future<void> saveHistory(List<DownloadTask> tasks) async {
    final encoded = jsonEncode(tasks.map((task) => task.toJson()).toList());
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.keyDownloadHistory, encoded);
    } catch (_) {}
  }

  /// Loads task list from SharedPreferences
  Future<List<DownloadTask>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.keyDownloadHistory);
      if (raw == null || raw.isEmpty) return [];

      final List<dynamic> jsonList = jsonDecode(raw);
      return jsonList
          .map((item) => DownloadTask.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<List<DownloadTask>> loadDownloadReceipts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConstants.keyDownloadReceipts);
      if (raw == null || raw.isEmpty) return [];
      final List<dynamic> jsonList = jsonDecode(raw);
      return jsonList
          .map((item) => DownloadTask.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveDownloadReceipt(DownloadTask task) async {
    await saveDownloadReceipts([task]);
  }

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

  /// Calculates total size of downloaded files
  Future<int> calculateCacheSize() async {
    final dirPath = await getDownloadDirectory();
    return await PlatformFileHelper.calculateCacheSize(dirPath);
  }

  /// Clears download directory files
  Future<void> clearDownloads() async {
    final dirPath = await getDownloadDirectory();
    await PlatformFileHelper.clearDownloads(dirPath);
  }
}
