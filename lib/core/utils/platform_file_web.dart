import 'file_action_result.dart';

class PlatformFileHelper {
  static Future<String?> getDownloadDirectoryPath() async => null;
  static Future<bool> requestStoragePermissions() async => true;
  static Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async => false;
  static Future<bool?> galleryFileExists(
    String filePath, {
    required bool isImage,
  }) async => null;
  static Future<String?> galleryFileUri(
    String filePath, {
    required bool isImage,
  }) async => null;
  static Future<FileActionResult> openGalleryUri(String uri) async =>
      FileActionResult.unsupported;
  static Future<FileActionResult> shareGalleryUri(
    String uri, {
    String? text,
  }) async => FileActionResult.unsupported;
  static Future<int> calculateCacheSize(String? dirPath) async => 0;
  static Future<void> clearDownloads(String? dirPath) async {}
  static Future<void> deleteFile(String filePath) async {}
  static Future<String> renameFile(String filePath, String newPath) async =>
      filePath;
  static Future<List<int>> readFileHeader(
    String filePath, {
    int length = 64,
  }) async => const [];
  static Future<bool> isPlayableVideo(String filePath) async => false;
  static Future<FileActionResult> openFile(String filePath) async =>
      FileActionResult.unsupported;
  static Future<FileActionResult> shareFile(
    String filePath, {
    String? text,
  }) async => FileActionResult.unsupported;
  static bool fileExists(String filePath) => false;
  static Future<int> fileSize(String filePath) async => 0;
}
