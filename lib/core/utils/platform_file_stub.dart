import 'dart:io';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PlatformFileHelper {
  static Future<String?> getDownloadDirectoryPath() async {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = await getExternalStorageDirectory();
      if (dir != null) {
        final videosDir = Directory('${dir.path}/NimbleClip');
        if (!await videosDir.exists()) {
          await videosDir.create(recursive: true);
        }
        return videosDir.path;
      }
    }
    dir = await getApplicationDocumentsDirectory();
    final snapDir = Directory('${dir.path}/NimbleClip');
    if (!await snapDir.exists()) {
      await snapDir.create(recursive: true);
    }
    return snapDir.path;
  }

  static Future<bool> requestStoragePermissions() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final hasAccess = await Gal.hasAccess();
      return hasAccess || await Gal.requestAccess();
    }
    return true;
  }

  static Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
  }) async {
    if (isAudio) return true;
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      await Gal.putVideo(filePath);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<int> calculateCacheSize(String? dirPath) async {
    if (dirPath == null) return 0;
    try {
      final dir = Directory(dirPath);
      int totalSize = 0;
      if (await dir.exists()) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }
      return totalSize;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearDownloads(String? dirPath) async {
    if (dirPath == null) return;
    try {
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        for (final entity in dir.listSync()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<void> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await OpenFilex.open(filePath);
      }
    } catch (_) {}
  }

  static Future<void> shareFile(String filePath, {String? text}) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        // ignore: deprecated_member_use
        await Share.shareXFiles([XFile(filePath)], text: text);
      }
    } catch (_) {}
  }

  static bool fileExists(String filePath) {
    return File(filePath).existsSync();
  }

  /// Size of a partial download on disk, or 0 when there is nothing to resume.
  static Future<int> fileSize(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists() ? await file.length() : 0;
    } catch (_) {
      return 0;
    }
  }
}
