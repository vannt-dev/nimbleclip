import 'dart:io';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'file_action_result.dart';
import 'media_format_helper.dart';

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
      final hasAccess = await Gal.hasPermission();
      return hasAccess || await Gal.requestPermission();
    }
    return true;
  }

  /// Whether this platform has a shared music library the app can add to.
  ///
  /// Android only: iOS offers an app no way to add a file to the Music
  /// library, and the desktop builds keep downloads in their own folder.
  static bool get canSaveAudioToLibrary => Platform.isAndroid;

  /// Copies a video or picture to the gallery, or an audio file to the
  /// device's Music library (`Music/NimbleClip`). With a [folder] name, the
  /// file goes into that folder instead: `Pictures/<folder>`,
  /// `Movies/<folder>` or `Music/<folder>` on Android, an album of that
  /// name on iOS.
  ///
  /// On Android every file goes through the app's own MediaStore code, which
  /// dates the entry with the moment it was saved: pickers such as WhatsApp's
  /// sort by that date, and a file without one is listed under 1970.
  static Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
    String? folder,
  }) async {
    if (isAudio) return _saveAudioToLibrary(filePath, folder);
    if (Platform.isAndroid) {
      return _saveToMediaStore(filePath, isImage ? 'image' : 'video', folder);
    }
    try {
      final hasAccess = await Gal.hasPermission();
      if (!hasAccess) {
        final granted = await Gal.requestPermission();
        if (!granted) return false;
      }
      if (isImage) {
        await Gal.putImage(filePath, album: folder);
      } else {
        await Gal.putVideo(filePath, album: folder);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _saveAudioToLibrary(
    String filePath,
    String? folder,
  ) async {
    if (!canSaveAudioToLibrary) return false;
    return _saveToMediaStore(filePath, 'audio', folder);
  }

  static Future<bool> _saveToMediaStore(
    String filePath,
    String kind,
    String? folder,
  ) async {
    try {
      // Only Android 9 and older ask for anything here; newer systems let an
      // app add its own files to the shared library without a permission.
      final hasAccess = await Gal.hasPermission();
      if (!hasAccess) {
        final granted = await Gal.requestPermission();
        if (!granted) return false;
      }
      final fileName = _fileNameOf(filePath);
      final uri = await _mediaStoreChannel.invokeMethod<String>('saveMedia', {
        'path': filePath,
        'fileName': fileName,
        'mimeType': switch (kind) {
          'audio' => MediaFormatHelper.audioMimeType(fileName),
          'image' => MediaFormatHelper.imageMimeType(fileName),
          _ => MediaFormatHelper.videoMimeType(fileName),
        },
        'kind': kind,
        'folder': folder,
      });
      return uri != null;
    } catch (_) {
      return false;
    }
  }

  static String _fileNameOf(String filePath) =>
      filePath.replaceAll('\\', '/').split('/').last;

  /// Returns null on platforms where Gallery contents cannot be queried.
  static Future<bool?> galleryFileExists(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _mediaStoreChannel.invokeMethod<bool>('mediaExists', {
            'fileName': _fileNameOf(filePath),
            'isImage': isImage,
            'isAudio': isAudio,
          }) ??
          false;
    } on PlatformException {
      return null;
    }
  }

  static Future<String?> galleryFileUri(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) async {
    if (!Platform.isAndroid) return null;
    try {
      return await _mediaStoreChannel.invokeMethod<String>('findMediaUri', {
        'fileName': _fileNameOf(filePath),
        'isImage': isImage,
        'isAudio': isAudio,
      });
    } on PlatformException {
      return null;
    }
  }

  static Future<FileActionResult> openGalleryUri(String uri) async {
    if (!Platform.isAndroid) return FileActionResult.unsupported;
    try {
      final opened = await _mediaStoreChannel.invokeMethod<bool>(
        'openMediaUri',
        {'uri': uri},
      );
      return opened == true
          ? FileActionResult.success
          : FileActionResult.unsupported;
    } on PlatformException {
      return FileActionResult.failed;
    }
  }

  static Future<FileActionResult> shareGalleryUri(
    String uri, {
    String? text,
  }) async {
    if (!Platform.isAndroid) return FileActionResult.unsupported;
    try {
      final shared = await _mediaStoreChannel.invokeMethod<bool>(
        'shareMediaUri',
        {'uri': uri, 'text': text},
      );
      return shared == true
          ? FileActionResult.success
          : FileActionResult.unsupported;
    } on PlatformException {
      return FileActionResult.failed;
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

  static Future<FileActionResult> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return FileActionResult.fileMissing;
      final result = await OpenFilex.open(filePath);
      switch (result.type) {
        case ResultType.done:
          return FileActionResult.success;
        case ResultType.fileNotFound:
          return FileActionResult.fileMissing;
        case ResultType.noAppToOpen:
          return FileActionResult.unsupported;
        case ResultType.permissionDenied:
        case ResultType.error:
          return FileActionResult.failed;
      }
    } catch (_) {
      return FileActionResult.failed;
    }
  }

  static Future<FileActionResult> shareFile(
    String filePath, {
    String? text,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return FileActionResult.fileMissing;
      // ignore: deprecated_member_use
      await Share.shareXFiles([XFile(filePath)], text: text);
      return FileActionResult.success;
    } catch (_) {
      return FileActionResult.failed;
    }
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
