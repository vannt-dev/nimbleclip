import '../core/utils/platform_file.dart';

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
