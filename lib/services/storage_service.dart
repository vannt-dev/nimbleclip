import 'dart:convert';
import 'dart:io';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../models/download_task.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  /// Gets the local storage directory for saved videos
  Future<Directory> getDownloadDirectory() async {
    Directory? dir;
    if (Platform.isAndroid) {
      // Android Downloads directory or app files directory
      dir = await getExternalStorageDirectory();
      if (dir != null) {
        final videosDir = Directory('${dir.path}/SnapVideos');
        if (!await videosDir.exists()) {
          await videosDir.create(recursive: true);
        }
        return videosDir;
      }
    }
    dir = await getApplicationDocumentsDirectory();
    final snapDir = Directory('${dir.path}/SnapVideos');
    if (!await snapDir.exists()) {
      await snapDir.create(recursive: true);
    }
    return snapDir;
  }

  /// Request permissions for saving videos
  Future<bool> requestStoragePermissions() async {
    if (Platform.isAndroid) {
      final mediaStatus = await Permission.videos.request();
      if (mediaStatus.isGranted || mediaStatus.isLimited) return true;

      final storageStatus = await Permission.storage.request();
      return storageStatus.isGranted || storageStatus.isLimited;
    } else if (Platform.isIOS) {
      final photos = await Permission.photos.request();
      return photos.isGranted || photos.isLimited;
    }
    return true;
  }

  /// Saves video or audio to device gallery
  Future<bool> saveToGallery(String filePath, {bool isAudio = false}) async {
    if (isAudio) return true; // Audio is stored in app directory / documents
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      await Gal.putVideo(filePath);
      return true;
    } catch (e) {
      // Fallback silently if gal throws unsupported platform
      return false;
    }
  }

  /// Persists task list to SharedPreferences
  Future<void> saveHistory(List<DownloadTask> tasks) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = tasks.map((t) => t.toJson()).toList();
    await prefs.setString(AppConstants.keyDownloadHistory, jsonEncode(jsonList));
  }

  /// Loads task list from SharedPreferences
  Future<List<DownloadTask>> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.keyDownloadHistory);
    if (raw == null || raw.isEmpty) return [];

    try {
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
    try {
      final dir = await getDownloadDirectory();
      int totalSize = 0;
      if (await dir.exists()) {
        final entities = dir.listSync(recursive: true);
        for (final file in entities) {
          if (file is File) {
            totalSize += await file.length();
          }
        }
      }
      return totalSize;
    } catch (_) {
      return 0;
    }
  }

  /// Clears download directory files
  Future<void> clearDownloads() async {
    try {
      final dir = await getDownloadDirectory();
      if (await dir.exists()) {
        final entities = dir.listSync();
        for (final file in entities) {
          if (file is File) {
            await file.delete();
          }
        }
      }
    } catch (_) {}
  }
}
