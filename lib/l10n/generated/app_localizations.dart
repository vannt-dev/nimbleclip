import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_vi.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('vi'),
  ];

  /// No description provided for @appTagline.
  ///
  /// In en, this message translates to:
  /// **'Fast HD video and audio downloader'**
  String get appTagline;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navDownloads.
  ///
  /// In en, this message translates to:
  /// **'Downloads'**
  String get navDownloads;

  /// No description provided for @navSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// No description provided for @clipboardVideoDetected.
  ///
  /// In en, this message translates to:
  /// **'Video link detected in your clipboard!'**
  String get clipboardVideoDetected;

  /// No description provided for @pasteAndDownload.
  ///
  /// In en, this message translates to:
  /// **'Paste & Download'**
  String get pasteAndDownload;

  /// No description provided for @downloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading: {title} ({quality})'**
  String downloadStarted(String title, String quality);

  /// No description provided for @duplicateDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Already downloaded'**
  String get duplicateDownloadTitle;

  /// No description provided for @duplicateDownloadMessage.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This file has already been downloaded. Download it again?} other{{count} selected files have already been downloaded. Download them again?}}'**
  String duplicateDownloadMessage(num count);

  /// No description provided for @downloadAgain.
  ///
  /// In en, this message translates to:
  /// **'Download again'**
  String get downloadAgain;

  /// No description provided for @downloadAlreadyInProgress.
  ///
  /// In en, this message translates to:
  /// **'This file is already being downloaded.'**
  String get downloadAlreadyInProgress;

  /// No description provided for @viewProgress.
  ///
  /// In en, this message translates to:
  /// **'View progress'**
  String get viewProgress;

  /// No description provided for @platformSupported.
  ///
  /// In en, this message translates to:
  /// **'High-quality downloads from {platform} are supported!'**
  String platformSupported(String platform);

  /// No description provided for @quickGuide.
  ///
  /// In en, this message translates to:
  /// **'Quick start guide'**
  String get quickGuide;

  /// No description provided for @guideCopyTitle.
  ///
  /// In en, this message translates to:
  /// **'Copy a video link'**
  String get guideCopyTitle;

  /// No description provided for @guideCopyDescription.
  ///
  /// In en, this message translates to:
  /// **'Open YouTube, TikTok, Facebook, or X and choose Copy link.'**
  String get guideCopyDescription;

  /// No description provided for @guidePasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste the link into NimbleClip'**
  String get guidePasteTitle;

  /// No description provided for @guidePasteDescription.
  ///
  /// In en, this message translates to:
  /// **'Tap Paste or enter the URL in the field above.'**
  String get guidePasteDescription;

  /// No description provided for @guideDownloadTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a quality and download'**
  String get guideDownloadTitle;

  /// No description provided for @guideDownloadDescription.
  ///
  /// In en, this message translates to:
  /// **'Preview the video, then download an available video or audio format.'**
  String get guideDownloadDescription;

  /// No description provided for @clipboardPasted.
  ///
  /// In en, this message translates to:
  /// **'Link pasted from clipboard!'**
  String get clipboardPasted;

  /// No description provided for @pasteVideoLink.
  ///
  /// In en, this message translates to:
  /// **'Paste a video link'**
  String get pasteVideoLink;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @paste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get paste;

  /// No description provided for @analyzeAndDownload.
  ///
  /// In en, this message translates to:
  /// **'Analyze & Download'**
  String get analyzeAndDownload;

  /// No description provided for @videoOptions.
  ///
  /// In en, this message translates to:
  /// **'Video ({count})'**
  String videoOptions(int count);

  /// No description provided for @imageOptions.
  ///
  /// In en, this message translates to:
  /// **'Images ({count})'**
  String imageOptions(int count);

  /// No description provided for @imageLabel.
  ///
  /// In en, this message translates to:
  /// **'Image {index}'**
  String imageLabel(int index);

  /// No description provided for @videoLabel.
  ///
  /// In en, this message translates to:
  /// **'Video {index}'**
  String videoLabel(int index);

  /// No description provided for @audioOptions.
  ///
  /// In en, this message translates to:
  /// **'Audio ({count})'**
  String audioOptions(int count);

  /// No description provided for @selectDownloadQuality.
  ///
  /// In en, this message translates to:
  /// **'Choose download quality:'**
  String get selectDownloadQuality;

  /// No description provided for @selectImages.
  ///
  /// In en, this message translates to:
  /// **'Choose images:'**
  String get selectImages;

  /// No description provided for @selectVideos.
  ///
  /// In en, this message translates to:
  /// **'Choose videos:'**
  String get selectVideos;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect all'**
  String get deselectAll;

  /// No description provided for @downloadSelected.
  ///
  /// In en, this message translates to:
  /// **'Download ({count})'**
  String downloadSelected(int count);

  /// No description provided for @batchDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Downloading {count} selected media files.'**
  String batchDownloadStarted(int count);

  /// No description provided for @batchResults.
  ///
  /// In en, this message translates to:
  /// **'Analyzed links ({count})'**
  String batchResults(int count);

  /// No description provided for @batchLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Only the first {count} links will be analyzed.'**
  String batchLimitReached(int count);

  /// No description provided for @queueAll.
  ///
  /// In en, this message translates to:
  /// **'Queue all ({count})'**
  String queueAll(int count);

  /// No description provided for @recentLinks.
  ///
  /// In en, this message translates to:
  /// **'Recent links'**
  String get recentLinks;

  /// No description provided for @copyDiagnostics.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get copyDiagnostics;

  /// No description provided for @diagnosticsCopied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied'**
  String get diagnosticsCopied;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @downloadNow.
  ///
  /// In en, this message translates to:
  /// **'Download now'**
  String get downloadNow;

  /// No description provided for @downloadsTitle.
  ///
  /// In en, this message translates to:
  /// **'Download manager'**
  String get downloadsTitle;

  /// No description provided for @clearFinished.
  ///
  /// In en, this message translates to:
  /// **'Clear finished items'**
  String get clearFinished;

  /// No description provided for @tabAll.
  ///
  /// In en, this message translates to:
  /// **'All ({count})'**
  String tabAll(int count);

  /// No description provided for @tabDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading'**
  String get tabDownloading;

  /// No description provided for @tabDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded ({count})'**
  String tabDownloaded(int count);

  /// No description provided for @confirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete download'**
  String get confirmDeleteTitle;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete “{title}”?'**
  String confirmDeleteMessage(String title);

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @videoDeleted.
  ///
  /// In en, this message translates to:
  /// **'Video deleted.'**
  String get videoDeleted;

  /// No description provided for @clearFinishedTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear finished items'**
  String get clearFinishedTitle;

  /// No description provided for @clearFinishedMessage.
  ///
  /// In en, this message translates to:
  /// **'Remove all completed, failed, and cancelled items from the list? Downloaded files will remain on your device.'**
  String get clearFinishedMessage;

  /// No description provided for @noActiveDownloads.
  ///
  /// In en, this message translates to:
  /// **'No active downloads'**
  String get noActiveDownloads;

  /// No description provided for @noActiveDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'Downloads in progress will appear here.'**
  String get noActiveDownloadsDescription;

  /// No description provided for @noCompletedDownloads.
  ///
  /// In en, this message translates to:
  /// **'No downloaded videos yet'**
  String get noCompletedDownloads;

  /// No description provided for @noCompletedDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'Paste a video link to start downloading.'**
  String get noCompletedDownloadsDescription;

  /// No description provided for @emptyDownloadList.
  ///
  /// In en, this message translates to:
  /// **'Your download list is empty'**
  String get emptyDownloadList;

  /// No description provided for @emptyDownloadListDescription.
  ///
  /// In en, this message translates to:
  /// **'You have not downloaded any videos yet.'**
  String get emptyDownloadListDescription;

  /// No description provided for @newDownload.
  ///
  /// In en, this message translates to:
  /// **'New download'**
  String get newDownload;

  /// No description provided for @savedToGallery.
  ///
  /// In en, this message translates to:
  /// **'Video saved to your gallery!'**
  String get savedToGallery;

  /// No description provided for @gallerySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save to the gallery. Please check the app permission.'**
  String get gallerySaveFailed;

  /// No description provided for @resumeDownload.
  ///
  /// In en, this message translates to:
  /// **'Resume download'**
  String get resumeDownload;

  /// No description provided for @pauseDownload.
  ///
  /// In en, this message translates to:
  /// **'Pause download'**
  String get pauseDownload;

  /// No description provided for @cancelDownload.
  ///
  /// In en, this message translates to:
  /// **'Cancel download'**
  String get cancelDownload;

  /// No description provided for @paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get paused;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @downloadInterrupted.
  ///
  /// In en, this message translates to:
  /// **'The download was interrupted when the app closed. Try again.'**
  String get downloadInterrupted;

  /// No description provided for @networkTimeout.
  ///
  /// In en, this message translates to:
  /// **'The network request timed out. Check your connection and try again.'**
  String get networkTimeout;

  /// No description provided for @serverConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the server.'**
  String get serverConnectionFailed;

  /// No description provided for @downloadLinkExpired.
  ///
  /// In en, this message translates to:
  /// **'The download link expired ({code}). Analyze the video again.'**
  String downloadLinkExpired(int code);

  /// No description provided for @serverError.
  ///
  /// In en, this message translates to:
  /// **'The server returned error {code}.'**
  String serverError(String code);

  /// No description provided for @unknownNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Unknown network error.'**
  String get unknownNetworkError;

  /// No description provided for @invalidDownloadedMedia.
  ///
  /// In en, this message translates to:
  /// **'The server returned an invalid or unsupported media file.'**
  String get invalidDownloadedMedia;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @browserDownloadStarted.
  ///
  /// In en, this message translates to:
  /// **'Sent to your browser\'s download manager.'**
  String get browserDownloadStarted;

  /// No description provided for @view.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get view;

  /// No description provided for @saved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get saved;

  /// No description provided for @saveToGallery.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveToGallery;

  /// No description provided for @share.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get share;

  /// No description provided for @shareFromNimbleClip.
  ///
  /// In en, this message translates to:
  /// **'Downloaded with NimbleClip: {title}'**
  String shareFromNimbleClip(String title);

  /// No description provided for @openWith.
  ///
  /// In en, this message translates to:
  /// **'Open with'**
  String get openWith;

  /// No description provided for @localFileMissing.
  ///
  /// In en, this message translates to:
  /// **'The downloaded file was not found. It may have been deleted.'**
  String get localFileMissing;

  /// No description provided for @noAppForFile.
  ///
  /// In en, this message translates to:
  /// **'No installed app can open this file type.'**
  String get noAppForFile;

  /// No description provided for @fileOpenFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open this file.'**
  String get fileOpenFailed;

  /// No description provided for @fileShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share this file.'**
  String get fileShareFailed;

  /// No description provided for @noVideoSource.
  ///
  /// In en, this message translates to:
  /// **'No video source is available.'**
  String get noVideoSource;

  /// No description provided for @videoPlaybackError.
  ///
  /// In en, this message translates to:
  /// **'Playback error: {error}'**
  String videoPlaybackError(String error);

  /// No description provided for @downloadThisVideo.
  ///
  /// In en, this message translates to:
  /// **'Download this video'**
  String get downloadThisVideo;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @languageSection.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageSection;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'Use device language'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageVietnamese.
  ///
  /// In en, this message translates to:
  /// **'Vietnamese'**
  String get languageVietnamese;

  /// No description provided for @appearanceSection.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearanceSection;

  /// No description provided for @themeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In en, this message translates to:
  /// **'Use system theme'**
  String get themeSystem;

  /// No description provided for @qualitySection.
  ///
  /// In en, this message translates to:
  /// **'Preferred video quality'**
  String get qualitySection;

  /// No description provided for @qualityHighestTitle.
  ///
  /// In en, this message translates to:
  /// **'Highest available (1080p / 2K / 4K)'**
  String get qualityHighestTitle;

  /// No description provided for @qualityHighestDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically choose the sharpest available resolution'**
  String get qualityHighestDescription;

  /// No description provided for @quality720Title.
  ///
  /// In en, this message translates to:
  /// **'HD (720p)'**
  String get quality720Title;

  /// No description provided for @quality720Description.
  ///
  /// In en, this message translates to:
  /// **'Balance quality and file size'**
  String get quality720Description;

  /// No description provided for @quality480Title.
  ///
  /// In en, this message translates to:
  /// **'Data saver (480p SD)'**
  String get quality480Title;

  /// No description provided for @quality480Description.
  ///
  /// In en, this message translates to:
  /// **'Smaller files and faster mobile downloads'**
  String get quality480Description;

  /// No description provided for @quality360Title.
  ///
  /// In en, this message translates to:
  /// **'Maximum data saving (360p)'**
  String get quality360Title;

  /// No description provided for @quality360Description.
  ///
  /// In en, this message translates to:
  /// **'Choose the smallest available video file'**
  String get quality360Description;

  /// No description provided for @qualityAudioTitle.
  ///
  /// In en, this message translates to:
  /// **'Audio only (MP3/M4A)'**
  String get qualityAudioTitle;

  /// No description provided for @qualityAudioDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically select an available audio format'**
  String get qualityAudioDescription;

  /// No description provided for @downloadStorageSection.
  ///
  /// In en, this message translates to:
  /// **'Downloads & Storage'**
  String get downloadStorageSection;

  /// No description provided for @autoSaveGallery.
  ///
  /// In en, this message translates to:
  /// **'Automatically save to gallery'**
  String get autoSaveGallery;

  /// No description provided for @autoSaveGalleryDescription.
  ///
  /// In en, this message translates to:
  /// **'Add media to your gallery after each download'**
  String get autoSaveGalleryDescription;

  /// No description provided for @removeCacheAfterGallery.
  ///
  /// In en, this message translates to:
  /// **'Remove local copy after saving'**
  String get removeCacheAfterGallery;

  /// No description provided for @removeCacheAfterGalleryDescription.
  ///
  /// In en, this message translates to:
  /// **'Avoid duplicate storage; the Gallery copy stays available'**
  String get removeCacheAfterGalleryDescription;

  /// No description provided for @allowExternalServices.
  ///
  /// In en, this message translates to:
  /// **'Allow external extraction services'**
  String get allowExternalServices;

  /// No description provided for @allowExternalServicesDescription.
  ///
  /// In en, this message translates to:
  /// **'Required for TikTok, X, and some Facebook or Instagram posts. The public post URL may be sent to these services.'**
  String get allowExternalServicesDescription;

  /// No description provided for @concurrentDownloads.
  ///
  /// In en, this message translates to:
  /// **'Simultaneous downloads'**
  String get concurrentDownloads;

  /// No description provided for @concurrentDownloadsDescription.
  ///
  /// In en, this message translates to:
  /// **'More downloads can be faster but use more bandwidth and battery'**
  String get concurrentDownloadsDescription;

  /// No description provided for @autoDetectClipboard.
  ///
  /// In en, this message translates to:
  /// **'Detect clipboard links automatically'**
  String get autoDetectClipboard;

  /// No description provided for @autoDetectClipboardDescription.
  ///
  /// In en, this message translates to:
  /// **'Check for a video link when the app opens'**
  String get autoDetectClipboardDescription;

  /// No description provided for @downloadedMediaSize.
  ///
  /// In en, this message translates to:
  /// **'Downloaded media size'**
  String get downloadedMediaSize;

  /// No description provided for @clearCacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear downloaded files?'**
  String get clearCacheTitle;

  /// No description provided for @clearCacheMessage.
  ///
  /// In en, this message translates to:
  /// **'All media stored in NimbleClip\'s download directory will be deleted.'**
  String get clearCacheMessage;

  /// No description provided for @deleteAll.
  ///
  /// In en, this message translates to:
  /// **'Delete all'**
  String get deleteAll;

  /// No description provided for @cacheCleared.
  ///
  /// In en, this message translates to:
  /// **'Downloaded files cleared.'**
  String get cacheCleared;

  /// No description provided for @cleanUp.
  ///
  /// In en, this message translates to:
  /// **'Clean up'**
  String get cleanUp;

  /// No description provided for @aboutSection.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutSection;

  /// No description provided for @version.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get version;

  /// No description provided for @supportedPlatforms.
  ///
  /// In en, this message translates to:
  /// **'Supported platforms'**
  String get supportedPlatforms;

  /// No description provided for @supportedPlatformsDescription.
  ///
  /// In en, this message translates to:
  /// **'YouTube, TikTok, Facebook, Instagram, X, and direct links'**
  String get supportedPlatformsDescription;

  /// No description provided for @githubSource.
  ///
  /// In en, this message translates to:
  /// **'GitHub source'**
  String get githubSource;

  /// No description provided for @invalidLink.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid http or https video URL.'**
  String get invalidLink;

  /// No description provided for @noDownloadStreams.
  ///
  /// In en, this message translates to:
  /// **'No downloadable stream was found for this link.'**
  String get noDownloadStreams;

  /// No description provided for @youtubeInvalidId.
  ///
  /// In en, this message translates to:
  /// **'No valid YouTube video ID was found in this link.'**
  String get youtubeInvalidId;

  /// No description provided for @videoAndAudioLabel.
  ///
  /// In en, this message translates to:
  /// **'{quality} (Video + Audio)'**
  String videoAndAudioLabel(String quality);

  /// No description provided for @audioM4aLabel.
  ///
  /// In en, this message translates to:
  /// **'M4A audio ({kbps} kbps)'**
  String audioM4aLabel(int kbps);

  /// No description provided for @videoBitrateLabel.
  ///
  /// In en, this message translates to:
  /// **'{quality} ({kbps} kbps)'**
  String videoBitrateLabel(String quality, int kbps);

  /// No description provided for @youtubeLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not load the YouTube page: {error}'**
  String youtubeLoadFailed(String error);

  /// No description provided for @youtubeNoPlayerData.
  ///
  /// In en, this message translates to:
  /// **'YouTube did not return player data. The video may be private or age-restricted.'**
  String get youtubeNoPlayerData;

  /// No description provided for @youtubeInvalidData.
  ///
  /// In en, this message translates to:
  /// **'YouTube returned invalid data: {error}'**
  String youtubeInvalidData(String error);

  /// No description provided for @youtubePlaybackRejected.
  ///
  /// In en, this message translates to:
  /// **'YouTube refused to play this video: {reason}'**
  String youtubePlaybackRejected(String reason);

  /// No description provided for @youtubeCipherUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This video uses a protected signature stream that the Web build cannot decode. Use the Android, iOS, or Desktop app instead.'**
  String get youtubeCipherUnsupported;

  /// No description provided for @youtubeNoStreams.
  ///
  /// In en, this message translates to:
  /// **'No downloadable stream was found for this YouTube video.'**
  String get youtubeNoStreams;

  /// No description provided for @xInvalidPost.
  ///
  /// In en, this message translates to:
  /// **'No post ID was found in this X / Twitter link. Use a link like x.com/<account>/status/<id>.'**
  String get xInvalidPost;

  /// No description provided for @xNoVideo.
  ///
  /// In en, this message translates to:
  /// **'This post has no downloadable video, or the account is protected.'**
  String get xNoVideo;

  /// No description provided for @originalMp4.
  ///
  /// In en, this message translates to:
  /// **'MP4 (Original quality)'**
  String get originalMp4;

  /// No description provided for @xPostBy.
  ///
  /// In en, this message translates to:
  /// **'Post by @{handle}'**
  String xPostBy(String handle);

  /// No description provided for @tiktokServiceStatus.
  ///
  /// In en, this message translates to:
  /// **'TikTok returned status {status}. Try again in a few minutes.'**
  String tiktokServiceStatus(int status);

  /// No description provided for @tiktokConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not connect to the TikTok service: {error}'**
  String tiktokConnectionFailed(String error);

  /// No description provided for @tiktokInvalidData.
  ///
  /// In en, this message translates to:
  /// **'Could not read the TikTok video data. The link may have been deleted or made private.'**
  String get tiktokInvalidData;

  /// No description provided for @noWatermark.
  ///
  /// In en, this message translates to:
  /// **'No watermark'**
  String get noWatermark;

  /// No description provided for @withWatermark.
  ///
  /// In en, this message translates to:
  /// **'With TikTok watermark'**
  String get withWatermark;

  /// No description provided for @originalSound.
  ///
  /// In en, this message translates to:
  /// **'Original sound'**
  String get originalSound;

  /// No description provided for @audioMp3Label.
  ///
  /// In en, this message translates to:
  /// **'MP3 audio ({title})'**
  String audioMp3Label(String title);

  /// No description provided for @tiktokNoStreams.
  ///
  /// In en, this message translates to:
  /// **'TikTok did not return any downloadable streams for this video.'**
  String get tiktokNoStreams;

  /// No description provided for @instagramInvalidPost.
  ///
  /// In en, this message translates to:
  /// **'Could not recognize this Instagram link. Use a post, reel, story or highlight link.'**
  String get instagramInvalidPost;

  /// No description provided for @instagramLoginRequired.
  ///
  /// In en, this message translates to:
  /// **'Instagram requires a login for this post. Only public Reels and videos can be downloaded.'**
  String get instagramLoginRequired;

  /// No description provided for @linkAccessFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not access this link: {error}'**
  String linkAccessFailed(String error);

  /// No description provided for @directMediaLink.
  ///
  /// In en, this message translates to:
  /// **'Direct media link'**
  String get directMediaLink;

  /// No description provided for @originalAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio (Original)'**
  String get originalAudio;

  /// No description provided for @originalVideo.
  ///
  /// In en, this message translates to:
  /// **'Video (Original)'**
  String get originalVideo;

  /// No description provided for @genericNoVideo.
  ///
  /// In en, this message translates to:
  /// **'No video was found at this link. Check the URL or paste a direct .mp4 file link.'**
  String get genericNoVideo;

  /// No description provided for @embeddedVideo.
  ///
  /// In en, this message translates to:
  /// **'Embedded video (Web)'**
  String get embeddedVideo;

  /// No description provided for @facebookNoVideo.
  ///
  /// In en, this message translates to:
  /// **'Could not extract media from this Facebook post. Make sure it is public; private posts and closed groups require a login.'**
  String get facebookNoVideo;

  /// No description provided for @highQuality720.
  ///
  /// In en, this message translates to:
  /// **'HD 720p (High quality)'**
  String get highQuality720;

  /// No description provided for @standardQuality480.
  ///
  /// In en, this message translates to:
  /// **'SD 480p (Standard)'**
  String get standardQuality480;

  /// No description provided for @invalidVideoUrl.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid video URL using http or https.'**
  String get invalidVideoUrl;

  /// No description provided for @unableToAnalyze.
  ///
  /// In en, this message translates to:
  /// **'This link could not be analyzed.'**
  String get unableToAnalyze;

  /// No description provided for @externalServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'External extraction services are disabled in Settings. Enable them to download this post.'**
  String get externalServicesDisabled;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'vi'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'vi':
      return AppLocalizationsVi();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
