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
  static Future<void> openFile(String filePath) async {}
  static Future<void> shareFile(String filePath, {String? text}) async {}
  static bool fileExists(String filePath) => false;
  static Future<int> fileSize(String filePath) async => 0;
}
