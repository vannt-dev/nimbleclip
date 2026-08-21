class PlatformFileHelper {
  static Future<String?> getDownloadDirectoryPath() async => null;
  static Future<bool> requestStoragePermissions() async => true;
  static Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async => false;
  static Future<int> calculateCacheSize(String? dirPath) async => 0;
  static Future<void> clearDownloads(String? dirPath) async {}
  static Future<void> deleteFile(String filePath) async {}
  static Future<void> openFile(String filePath) async {}
  static Future<void> shareFile(String filePath, {String? text}) async {}
  static bool fileExists(String filePath) => false;
  static Future<int> fileSize(String filePath) async => 0;
}
