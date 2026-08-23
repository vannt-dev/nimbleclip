import 'dart:io';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

class PlatformFileHelper {
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'com.vannt.nimbleclip/media_store',
  );
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
    bool isImage = false,
  }) async {
    if (isAudio) return true;
    try {
      final hasAccess = await Gal.hasAccess();
      if (!hasAccess) {
        final granted = await Gal.requestAccess();
        if (!granted) return false;
      }
      if (isImage) {
        await Gal.putImage(filePath);
      } else {
        await Gal.putVideo(filePath);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Returns null on platforms where Gallery contents cannot be queried.
  static Future<bool?> galleryFileExists(
    String filePath, {
    required bool isImage,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      final fileName = filePath.replaceAll('\\', '/').split('/').last;
      return await _mediaStoreChannel.invokeMethod<bool>('mediaExists', {
            'fileName': fileName,
            'isImage': isImage,
          }) ??
          false;
    } on PlatformException {
      return null;
    }
  }

  static Future<int> calculateCacheSize(String? dirPath) async {
    if (dirPath == null) return 0;
    try {
      final dir = Directory(dirPath);
      int totalSize = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
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
        await for (final entity in dir.list()) {
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

  static Future<String> renameFile(String filePath, String newPath) async {
    if (filePath == newPath) return filePath;
    final source = File(filePath);
    if (!await source.exists()) return filePath;
    final destination = File(newPath);
    if (await destination.exists()) {
      await destination.delete();
    }
    return (await source.rename(newPath)).path;
  }

  static Future<List<int>> readFileHeader(
    String filePath, {
    int length = 64,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return const [];
    final handle = await file.open();
    try {
      return await handle.read(length);
    } finally {
      await handle.close();
    }
  }

  static Future<bool> isPlayableVideo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return false;
    final controller = VideoPlayerController.file(file);
    try {
      await controller.initialize();
      return controller.value.isInitialized &&
          controller.value.duration > Duration.zero &&
          controller.value.size.width > 0 &&
          controller.value.size.height > 0;
    } catch (_) {
      return false;
    } finally {
      await controller.dispose();
    }
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
