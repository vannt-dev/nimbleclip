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
