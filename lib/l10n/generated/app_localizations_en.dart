// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTagline => 'Fast HD video and audio downloader';

  @override
  String get navHome => 'Home';

  @override
  String get navDownloads => 'Downloads';

  @override
  String get navSettings => 'Settings';

  @override
  String get clipboardVideoDetected => 'Video link detected in your clipboard!';

  @override
  String get pasteAndDownload => 'Paste & Download';

  @override
  String downloadStarted(String title, String quality) {
    return 'Downloading: $title ($quality)';
  }

  @override
  String get duplicateDownloadTitle => 'Already downloaded';

  @override
  String duplicateDownloadMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count selected files have already been downloaded. Download them again?',
      one: 'This file has already been downloaded. Download it again?',
    );
    return '$_temp0';
  }

  @override
  String get downloadAgain => 'Download again';

  @override
  String get downloadAlreadyInProgress =>
      'This file is already being downloaded.';

  @override
  String get viewProgress => 'View progress';

  @override
  String platformSupported(String platform) {
    return 'High-quality downloads from $platform are supported!';
  }

  @override
  String get quickGuide => 'Quick start guide';

  @override
  String get guideCopyTitle => 'Copy a video link';

  @override
  String get guideCopyDescription =>
      'Open YouTube, TikTok, Facebook, or X and choose Copy link.';

  @override
  String get guidePasteTitle => 'Paste the link into NimbleClip';

  @override
  String get guidePasteDescription =>
      'Tap Paste or enter the URL in the field above.';

  @override
  String get guideDownloadTitle => 'Choose a quality and download';

  @override
  String get guideDownloadDescription =>
      'Preview the video, then download an available video or audio format.';

  @override
  String get clipboardPasted => 'Link pasted from clipboard!';

  @override
  String get pasteVideoLink => 'Paste a video link';

  @override
  String get clear => 'Clear';

  @override
  String get paste => 'Paste';

  @override
  String get analyzeAndDownload => 'Analyze & Download';

  @override
  String videoOptions(int count) {
    return 'Video ($count)';
  }

  @override
  String imageOptions(int count) {
    return 'Images ($count)';
  }

  @override
  String imageLabel(int index) {
    return 'Image $index';
  }

  @override
  String audioOptions(int count) {
    return 'Audio ($count)';
  }

  @override
  String get selectDownloadQuality => 'Choose download quality:';

  @override
  String get selectImages => 'Choose images:';

  @override
  String get selectAll => 'Select all';

  @override
  String get deselectAll => 'Deselect all';

  @override
  String downloadSelected(int count) {
    return 'Download selected ($count)';
  }

  @override
  String batchDownloadStarted(int count) {
    return 'Downloading $count selected images.';
  }

  @override
  String get preview => 'Preview';

  @override
  String get downloadNow => 'Download now';

  @override
  String get downloadsTitle => 'Download manager';

  @override
  String get clearFinished => 'Clear finished items';

  @override
  String tabAll(int count) {
    return 'All ($count)';
  }

  @override
  String get tabDownloading => 'Downloading';

  @override
  String tabDownloaded(int count) {
    return 'Downloaded ($count)';
  }

  @override
  String get confirmDeleteTitle => 'Delete download';

  @override
  String confirmDeleteMessage(String title) {
    return 'Are you sure you want to delete “$title”?';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get videoDeleted => 'Video deleted.';

  @override
  String get clearFinishedTitle => 'Clear finished items';

  @override
  String get clearFinishedMessage =>
      'Remove all completed, failed, and cancelled items from the list? Downloaded files will remain on your device.';

  @override
  String get noActiveDownloads => 'No active downloads';

  @override
  String get noActiveDownloadsDescription =>
      'Downloads in progress will appear here.';

  @override
  String get noCompletedDownloads => 'No downloaded videos yet';

  @override
  String get noCompletedDownloadsDescription =>
      'Paste a video link to start downloading.';

  @override
  String get emptyDownloadList => 'Your download list is empty';

  @override
  String get emptyDownloadListDescription =>
      'You have not downloaded any videos yet.';

  @override
  String get newDownload => 'New download';

  @override
  String get savedToGallery => 'Video saved to your gallery!';

  @override
  String get gallerySaveFailed =>
      'Could not save to the gallery. Please check the app permission.';

  @override
  String get gallerySaveFailedShort => 'Could not save to the gallery.';

  @override
  String get resumeDownload => 'Resume download';

  @override
  String get pauseDownload => 'Pause download';

  @override
  String get cancelDownload => 'Cancel download';

  @override
  String get paused => 'Paused';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String get downloadInterrupted =>
      'The download was interrupted when the app closed. Try again.';

  @override
  String get networkTimeout =>
      'The network request timed out. Check your connection and try again.';

  @override
  String get serverConnectionFailed => 'Could not connect to the server.';

  @override
  String downloadLinkExpired(int code) {
    return 'The download link expired ($code). Analyze the video again.';
  }

  @override
  String serverError(String code) {
    return 'The server returned error $code.';
  }

  @override
  String get unknownNetworkError => 'Unknown network error.';

  @override
  String get invalidDownloadedMedia =>
      'The server returned an invalid or unsupported media file.';

  @override
  String get retry => 'Retry';

  @override
  String get browserDownloadStarted =>
      'Sent to your browser\'s download manager.';

  @override
  String get view => 'View';

  @override
  String get saved => 'Saved';

  @override
  String get saveToGallery => 'Save';

  @override
  String get share => 'Share';

  @override
  String shareFromNimbleClip(String title) {
    return 'Downloaded with NimbleClip: $title';
  }

  @override
  String get openWith => 'Open with';

  @override
  String get localFileMissing =>
      'The downloaded file was not found. It may have been deleted.';

  @override
  String get noAppForFile => 'No installed app can open this file type.';

  @override
  String get fileOpenFailed => 'Could not open this file.';

  @override
  String get fileShareFailed => 'Could not share this file.';

  @override
  String get noVideoSource => 'No video source is available.';

  @override
  String videoPlaybackError(String error) {
    return 'Playback error: $error';
  }

  @override
  String get downloadThisVideo => 'Download this video';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get languageSection => 'Language';

  @override
  String get languageSystem => 'Use device language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageVietnamese => 'Vietnamese';

  @override
  String get appearanceSection => 'Appearance';

  @override
  String get themeDark => 'Dark';

  @override
  String get themeLight => 'Light';

  @override
  String get themeSystem => 'Use system theme';

  @override
  String get qualitySection => 'Preferred video quality';

  @override
  String get qualityHighestTitle => 'Highest available (1080p / 2K / 4K)';

  @override
  String get qualityHighestDescription =>
      'Automatically choose the sharpest available resolution';

  @override
  String get quality720Title => 'HD (720p)';

  @override
  String get quality720Description => 'Balance quality and file size';

  @override
  String get quality480Title => 'Data saver (480p SD)';

  @override
  String get quality480Description =>
      'Smaller files and faster mobile downloads';

  @override
  String get quality360Title => 'Maximum data saving (360p)';

  @override
  String get quality360Description =>
      'Choose the smallest available video file';

  @override
  String get qualityAudioTitle => 'Audio only (MP3/M4A)';

  @override
  String get qualityAudioDescription =>
      'Automatically select an available audio format';

  @override
  String get downloadStorageSection => 'Downloads & Storage';

  @override
  String get autoSaveGallery => 'Automatically save to gallery';

  @override
  String get autoSaveGalleryDescription =>
      'Add media to your gallery after each download';

  @override
  String get autoDetectClipboard => 'Detect clipboard links automatically';

  @override
  String get autoDetectClipboardDescription =>
      'Check for a video link when the app opens';

  @override
  String get downloadedMediaSize => 'Downloaded media size';

  @override
  String get clearCacheTitle => 'Clear downloaded files?';

  @override
  String get clearCacheMessage =>
      'All media stored in NimbleClip\'s download directory will be deleted.';

  @override
  String get deleteAll => 'Delete all';

  @override
  String get cacheCleared => 'Downloaded files cleared.';

  @override
  String get cleanUp => 'Clean up';

  @override
  String get aboutSection => 'About';

  @override
  String get version => 'Version';

  @override
  String get supportedPlatforms => 'Supported platforms';

  @override
  String get supportedPlatformsDescription =>
      'YouTube, TikTok, Facebook, Instagram, X, and direct links';

  @override
  String get githubSource => 'GitHub source';

  @override
  String get invalidLink => 'Enter a valid http or https video URL.';

  @override
  String get noDownloadStreams =>
      'No downloadable stream was found for this link.';

  @override
  String get youtubeInvalidId =>
      'No valid YouTube video ID was found in this link.';

  @override
  String videoAndAudioLabel(String quality) {
    return '$quality (Video + Audio)';
  }

  @override
  String audioM4aLabel(int kbps) {
    return 'M4A audio ($kbps kbps)';
  }

  @override
  String youtubeLoadFailed(String error) {
    return 'Could not load the YouTube page: $error';
  }

  @override
  String get youtubeNoPlayerData =>
      'YouTube did not return player data. The video may be private or age-restricted.';

  @override
  String youtubeInvalidData(String error) {
    return 'YouTube returned invalid data: $error';
  }

  @override
  String youtubePlaybackRejected(String reason) {
    return 'YouTube refused to play this video: $reason';
  }

  @override
  String get youtubeCipherUnsupported =>
      'This video uses a protected signature stream that the Web build cannot decode. Use the Android, iOS, or Desktop app instead.';

  @override
  String get youtubeNoStreams =>
      'No downloadable stream was found for this YouTube video.';

  @override
  String get xInvalidPost =>
      'No post ID was found in this X / Twitter link. Use a link like x.com/<account>/status/<id>.';

  @override
  String get xNoVideo =>
      'This post has no downloadable video, or the account is protected.';

  @override
  String get originalMp4 => 'MP4 (Original quality)';

  @override
  String xPostBy(String handle) {
    return 'Post by @$handle';
  }

  @override
  String tiktokServiceStatus(int status) {
    return 'TikTok returned status $status. Try again in a few minutes.';
  }

  @override
  String tiktokConnectionFailed(String error) {
    return 'Could not connect to the TikTok service: $error';
  }

  @override
  String get tiktokInvalidData =>
      'Could not read the TikTok video data. The link may have been deleted or made private.';

  @override
  String get noWatermark => 'No watermark';

  @override
  String get withWatermark => 'With TikTok watermark';

  @override
  String get originalSound => 'Original sound';

  @override
  String audioMp3Label(String title) {
    return 'MP3 audio ($title)';
  }

  @override
  String get tiktokNoStreams =>
      'TikTok did not return any downloadable streams for this video.';

  @override
  String get instagramInvalidPost =>
      'Could not recognize this Instagram post. Use an instagram.com/reel/<code> or instagram.com/p/<code> link.';

  @override
  String get instagramLoginRequired =>
      'Instagram requires a login for this post. Only public Reels and videos can be downloaded.';

  @override
  String linkAccessFailed(String error) {
    return 'Could not access this link: $error';
  }

  @override
  String get directMediaLink => 'Direct media link';

  @override
  String get originalAudio => 'Audio (Original)';

  @override
  String get originalVideo => 'Video (Original)';

  @override
  String get genericNoVideo =>
      'No video was found at this link. Check the URL or paste a direct .mp4 file link.';

  @override
  String get embeddedVideo => 'Embedded video (Web)';

  @override
  String get facebookNoVideo =>
      'Could not extract a Facebook video. Make sure it is public; private and closed-group videos require a login.';

  @override
  String get highQuality720 => 'HD 720p (High quality)';

  @override
  String get standardQuality480 => 'SD 480p (Standard)';

  @override
  String get invalidVideoUrl => 'Enter a valid video URL using http or https.';

  @override
  String get unableToAnalyze => 'This link could not be analyzed.';
}
