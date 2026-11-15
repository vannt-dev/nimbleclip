import '../core/utils/platform_file.dart';

abstract interface class MediaFileActions {
  bool exists(String filePath);
  Future<void> delete(String filePath);

  /// Whether the copy in the shared library is still there: the gallery for a
  /// video or picture, the Music library when [isAudio] is set.
  Future<bool?> galleryExists(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  });
  Future<String?> galleryUri(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  });
  Future<FileActionResult> openLocal(String filePath);
  Future<FileActionResult> shareLocal(String filePath, {String? text});
  Future<FileActionResult> openGallery(String uri);
  Future<FileActionResult> shareGallery(String uri, {String? text});
}

class PlatformMediaFileActions implements MediaFileActions {
  const PlatformMediaFileActions();

  @override
  bool exists(String filePath) => PlatformFileHelper.fileExists(filePath);

  @override
  Future<void> delete(String filePath) =>
      PlatformFileHelper.deleteFile(filePath);

  @override
  Future<bool?> galleryExists(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) => PlatformFileHelper.galleryFileExists(
    filePath,
    isImage: isImage,
    isAudio: isAudio,
  );

  @override
  Future<String?> galleryUri(
    String filePath, {
    required bool isImage,
    bool isAudio = false,
  }) => PlatformFileHelper.galleryFileUri(
    filePath,
    isImage: isImage,
    isAudio: isAudio,
  );

  @override
  Future<FileActionResult> openLocal(String filePath) =>
      PlatformFileHelper.openFile(filePath);

  @override
  Future<FileActionResult> shareLocal(String filePath, {String? text}) =>
      PlatformFileHelper.shareFile(filePath, text: text);

  @override
  Future<FileActionResult> openGallery(String uri) =>
      PlatformFileHelper.openGalleryUri(uri);

  @override
  Future<FileActionResult> shareGallery(String uri, {String? text}) =>
      PlatformFileHelper.shareGalleryUri(uri, text: text);
}
