import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/platform_file.dart';
import '../core/utils/save_folder_name.dart';

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

  /// Saves a video or picture to the device gallery, or audio to its Music
  /// library.
  Future<bool> saveToGallery(
    String filePath, {
    bool isAudio = false,
    bool isImage = false,
  }) async {
    return await PlatformFileHelper.saveToGallery(
      filePath,
      isAudio: isAudio,
      isImage: isImage,
      folder: await _saveFolderName(),
    );
  }

  /// Puts the lyrics file at [lyricsPath] beside the audio file [audioUri]
  /// names in the device's Music library. Returns whether it is there.
  Future<bool> saveLyricsToLibrary(
    String lyricsPath, {
    required String audioUri,
  }) => PlatformFileHelper.saveLyricsBeside(lyricsPath, audioUri: audioUri);

  /// The folder chosen in Settings, read at save time so a download that
  /// finishes in the background uses the current choice. Null for the
  /// default places, and for anything stored that is not a valid name.
  Future<String?> _saveFolderName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final stored = prefs.getString(AppConstants.keySaveFolderName);
      if (stored == null || SaveFolderName.problemWith(stored) != null) {
        return null;
      }
      return SaveFolderName.normalize(stored);
    } catch (_) {
      return null;
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
