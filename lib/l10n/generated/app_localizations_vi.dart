// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Vietnamese (`vi`).
class AppLocalizationsVi extends AppLocalizations {
  AppLocalizationsVi([String locale = 'vi']) : super(locale);

  @override
  String get appTagline => 'Tải video và âm thanh HD nhanh chóng';

  @override
  String get navHome => 'Trang chủ';

  @override
  String get navDownloads => 'Tải về';

  @override
  String get navSettings => 'Cài đặt';

  @override
  String get clipboardVideoDetected =>
      'Đã phát hiện liên kết video trong clipboard!';

  @override
  String get pasteAndDownload => 'Dán & Tải';

  @override
  String downloadStarted(String title, String quality) {
    return 'Đang tải: $title ($quality)';
  }

  @override
  String get duplicateDownloadTitle => 'Nội dung đã được tải';

  @override
  String duplicateDownloadMessage(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Có $count file đã được tải. Bạn có muốn tải lại không?',
      one: 'File này đã được tải. Bạn có muốn tải lại không?',
    );
    return '$_temp0';
  }

  @override
  String get downloadAgain => 'Tải lại';

  @override
  String get downloadAlreadyInProgress => 'File này đang được tải xuống.';

  @override
  String get viewProgress => 'Xem tiến trình';

  @override
  String platformSupported(String platform) {
    return 'Hỗ trợ tải video chất lượng cao từ $platform!';
  }

  @override
  String get quickGuide => 'Hướng dẫn nhanh';

  @override
  String get guideCopyTitle => 'Sao chép liên kết video';

  @override
  String get guideCopyDescription =>
      'Mở YouTube, TikTok, Facebook hoặc X và chọn Sao chép liên kết.';

  @override
  String get guidePasteTitle => 'Dán liên kết vào NimbleClip';

  @override
  String get guidePasteDescription => 'Nhấn Dán hoặc nhập URL vào ô phía trên.';

  @override
  String get guideDownloadTitle => 'Chọn chất lượng và tải về';

  @override
  String get guideDownloadDescription =>
      'Xem trước rồi tải định dạng video hoặc âm thanh đang có.';

  @override
  String get clipboardPasted => 'Đã dán liên kết từ clipboard!';

  @override
  String get pasteVideoLink => 'Dán liên kết video';

  @override
  String get clear => 'Xóa';

  @override
  String get paste => 'Dán';

  @override
  String get analyzeAndDownload => 'Phân tích & Tải';

  @override
  String videoOptions(int count) {
    return 'Video ($count)';
  }

  @override
  String imageOptions(int count) {
    return 'Ảnh ($count)';
  }

  @override
  String imageLabel(int index) {
    return 'Ảnh $index';
  }

  @override
  String videoLabel(int index) {
    return 'Video $index';
  }

  @override
  String audioOptions(int count) {
    return 'Âm thanh ($count)';
  }

  @override
  String get selectDownloadQuality => 'Chọn chất lượng tải về:';

  @override
  String get selectImages => 'Chọn ảnh:';

  @override
  String get selectVideos => 'Chọn video:';

  @override
  String get selectAll => 'Chọn tất cả';

  @override
  String get deselectAll => 'Bỏ chọn tất cả';

  @override
  String downloadSelected(int count) {
    return 'Tải xuống ($count)';
  }

  @override
  String batchDownloadStarted(int count) {
    return 'Đang tải $count file nội dung đã chọn.';
  }

  @override
  String batchResults(int count) {
    return 'Liên kết đã phân tích ($count)';
  }

  @override
  String batchLimitReached(int count) {
    return 'Chỉ $count liên kết đầu tiên được phân tích.';
  }

  @override
  String queueAll(int count) {
    return 'Thêm tất cả vào hàng đợi ($count)';
  }

  @override
  String get recentLinks => 'Liên kết gần đây';

  @override
  String get copyDiagnostics => 'Sao chép chẩn đoán';

  @override
  String get diagnosticsCopied => 'Đã sao chép thông tin chẩn đoán';

  @override
  String get preview => 'Xem trước';

  @override
  String get downloadNow => 'Tải về ngay';

  @override
  String get downloadsTitle => 'Quản lý tải về';

  @override
  String get clearFinished => 'Xóa các mục đã xong';

  @override
  String tabAll(int count) {
    return 'Tất cả ($count)';
  }

  @override
  String get tabDownloading => 'Đang tải';

  @override
  String tabDownloaded(int count) {
    return 'Đã tải ($count)';
  }

  @override
  String get confirmDeleteTitle => 'Xóa mục tải về';

  @override
  String confirmDeleteMessage(String title) {
    return 'Bạn có chắc muốn xóa “$title”?';
  }

  @override
  String get cancel => 'Hủy';

  @override
  String get delete => 'Xóa';

  @override
  String get videoDeleted => 'Đã xóa video.';

  @override
  String get clearFinishedTitle => 'Xóa các mục đã xong';

  @override
  String get clearFinishedMessage =>
      'Xóa toàn bộ mục đã tải xong, thất bại và đã hủy khỏi danh sách? File đã tải vẫn được giữ trên thiết bị.';

  @override
  String get noActiveDownloads => 'Không có tiến trình tải nào';

  @override
  String get noActiveDownloadsDescription =>
      'Các nội dung đang tải sẽ xuất hiện tại đây.';

  @override
  String get noCompletedDownloads => 'Chưa có video nào đã tải';

  @override
  String get noCompletedDownloadsDescription =>
      'Dán liên kết video để bắt đầu tải về.';

  @override
  String get emptyDownloadList => 'Danh sách tải về đang trống';

  @override
  String get emptyDownloadListDescription => 'Bạn chưa tải video nào.';

  @override
  String get newDownload => 'Tải video mới';

  @override
  String get savedToGallery => 'Đã lưu video vào thư viện!';

  @override
  String get gallerySaveFailed =>
      'Không thể lưu vào thư viện. Vui lòng kiểm tra quyền ứng dụng.';

  @override
  String get resumeDownload => 'Tiếp tục tải';

  @override
  String get pauseDownload => 'Tạm dừng';

  @override
  String get cancelDownload => 'Hủy tải';

  @override
  String get paused => 'Đã tạm dừng';

  @override
  String get downloadFailed => 'Tải xuống thất bại';

  @override
  String get downloadInterrupted =>
      'Tải bị gián đoạn khi ứng dụng đóng. Hãy thử lại.';

  @override
  String get networkTimeout =>
      'Hết thời gian chờ mạng. Hãy kiểm tra kết nối và thử lại.';

  @override
  String get serverConnectionFailed => 'Không kết nối được tới máy chủ.';

  @override
  String downloadLinkExpired(int code) {
    return 'Liên kết tải đã hết hạn ($code). Hãy phân tích lại video.';
  }

  @override
  String serverError(String code) {
    return 'Máy chủ trả về lỗi $code.';
  }

  @override
  String get unknownNetworkError => 'Lỗi mạng không xác định.';

  @override
  String get invalidDownloadedMedia =>
      'Máy chủ trả về file media không hợp lệ hoặc không được hỗ trợ.';

  @override
  String get retry => 'Thử lại';

  @override
  String get browserDownloadStarted =>
      'Đã chuyển sang trình tải xuống của trình duyệt.';

  @override
  String get view => 'Xem';

  @override
  String get saved => 'Đã lưu';

  @override
  String get saveToGallery => 'Lưu Album';

  @override
  String get share => 'Chia sẻ';

  @override
  String shareFromNimbleClip(String title) {
    return 'Tải bằng NimbleClip: $title';
  }

  @override
  String get openWith => 'Mở bằng';

  @override
  String get localFileMissing =>
      'Không tìm thấy file đã tải. File có thể đã bị xóa.';

  @override
  String get noAppForFile =>
      'Không có ứng dụng nào trên thiết bị có thể mở loại file này.';

  @override
  String get fileOpenFailed => 'Không thể mở file này.';

  @override
  String get fileShareFailed => 'Không thể chia sẻ file này.';

  @override
  String get noVideoSource => 'Không có nguồn video để phát.';

  @override
  String videoPlaybackError(String error) {
    return 'Lỗi phát video: $error';
  }

  @override
  String get downloadThisVideo => 'Tải video này';

  @override
  String get settingsTitle => 'Cài đặt';

  @override
  String get languageSection => 'Ngôn ngữ';

  @override
  String get languageSystem => 'Theo ngôn ngữ thiết bị';

  @override
  String get languageEnglish => 'Tiếng Anh';

  @override
  String get languageVietnamese => 'Tiếng Việt';

  @override
  String get appearanceSection => 'Giao diện';

  @override
  String get themeDark => 'Tối';

  @override
  String get themeLight => 'Sáng';

  @override
  String get themeSystem => 'Theo hệ thống';

  @override
  String get qualitySection => 'Chất lượng video ưu tiên';

  @override
  String get qualityHighestTitle => 'Cao nhất (1080p / 2K / 4K)';

  @override
  String get qualityHighestDescription =>
      'Tự động chọn độ phân giải sắc nét nhất hiện có';

  @override
  String get quality720Title => 'HD (720p)';

  @override
  String get quality720Description => 'Cân bằng giữa chất lượng và dung lượng';

  @override
  String get quality480Title => 'Tiết kiệm dữ liệu (480p SD)';

  @override
  String get quality480Description =>
      'File nhỏ hơn và tải nhanh hơn trên mạng di động';

  @override
  String get quality360Title => 'Tiết kiệm tối đa (360p)';

  @override
  String get quality360Description => 'Chọn file video nhỏ nhất hiện có';

  @override
  String get qualityAudioTitle => 'Chỉ tải âm thanh (MP3/M4A)';

  @override
  String get qualityAudioDescription =>
      'Tự động chọn định dạng âm thanh hiện có';

  @override
  String get downloadStorageSection => 'Tải về & Lưu trữ';

  @override
  String get autoSaveGallery => 'Tự động lưu vào thư viện';

  @override
  String get autoSaveGalleryDescription =>
      'Thêm nội dung vào thư viện sau khi tải xong';

  @override
  String get removeCacheAfterGallery => 'Xóa bản lưu tạm sau khi lưu';

  @override
  String get removeCacheAfterGalleryDescription =>
      'Tránh tốn dung lượng gấp đôi; bản trong Thư viện vẫn được giữ';

  @override
  String get allowExternalServices => 'Cho phép dịch vụ trích xuất bên ngoài';

  @override
  String get allowExternalServicesDescription =>
      'Cần cho TikTok, X và một số bài Facebook hoặc Instagram. URL bài công khai có thể được gửi tới các dịch vụ này.';

  @override
  String get concurrentDownloads => 'Số lượt tải đồng thời';

  @override
  String get concurrentDownloadsDescription =>
      'Tải nhiều có thể nhanh hơn nhưng dùng thêm mạng và pin';

  @override
  String get autoDetectClipboard => 'Tự động nhận diện liên kết clipboard';

  @override
  String get autoDetectClipboardDescription =>
      'Kiểm tra liên kết video khi mở ứng dụng';

  @override
  String get downloadedMediaSize => 'Dung lượng nội dung đã tải';

  @override
  String get clearCacheTitle => 'Xóa các file đã tải?';

  @override
  String get clearCacheMessage =>
      'Toàn bộ nội dung trong thư mục tải về của NimbleClip sẽ bị xóa.';

  @override
  String get deleteAll => 'Xóa tất cả';

  @override
  String get cacheCleared => 'Đã xóa các file tải về.';

  @override
  String get cleanUp => 'Dọn dẹp';

  @override
  String get aboutSection => 'Thông tin ứng dụng';

  @override
  String get version => 'Phiên bản';

  @override
  String get supportedPlatforms => 'Nền tảng hỗ trợ';

  @override
  String get supportedPlatformsDescription =>
      'YouTube, TikTok, Facebook, Instagram, X và liên kết trực tiếp';

  @override
  String get githubSource => 'Mã nguồn GitHub';

  @override
  String get invalidLink =>
      'Hãy nhập một liên kết video http hoặc https hợp lệ.';

  @override
  String get noDownloadStreams =>
      'Không tìm thấy luồng tải nào cho liên kết này.';

  @override
  String get youtubeInvalidId =>
      'Không tìm thấy Video ID YouTube hợp lệ trong liên kết.';

  @override
  String videoAndAudioLabel(String quality) {
    return '$quality (Video + Âm thanh)';
  }

  @override
  String audioM4aLabel(int kbps) {
    return 'Âm thanh M4A ($kbps kbps)';
  }

  @override
  String videoBitrateLabel(String quality, int kbps) {
    return '$quality ($kbps kbps)';
  }

  @override
  String youtubeLoadFailed(String error) {
    return 'Không tải được trang YouTube: $error';
  }

  @override
  String get youtubeNoPlayerData =>
      'YouTube không trả về dữ liệu trình phát. Video có thể ở chế độ riêng tư hoặc bị giới hạn độ tuổi.';

  @override
  String youtubeInvalidData(String error) {
    return 'Dữ liệu YouTube không hợp lệ: $error';
  }

  @override
  String youtubePlaybackRejected(String reason) {
    return 'YouTube từ chối phát video này: $reason';
  }

  @override
  String get youtubeCipherUnsupported =>
      'Video sử dụng luồng có chữ ký bảo vệ mà bản Web không giải mã được. Hãy dùng ứng dụng Android, iOS hoặc Desktop.';

  @override
  String get youtubeNoStreams =>
      'Không tìm thấy luồng tải nào cho video YouTube này.';

  @override
  String get xInvalidPost =>
      'Không tìm thấy ID bài đăng trong liên kết X / Twitter. Hãy dùng link dạng x.com/<tài khoản>/status/<id>.';

  @override
  String get xNoVideo =>
      'Bài đăng không có video tải được hoặc tài khoản đang được bảo vệ.';

  @override
  String get originalMp4 => 'MP4 (Chất lượng gốc)';

  @override
  String xPostBy(String handle) {
    return 'Bài đăng của @$handle';
  }

  @override
  String tiktokServiceStatus(int status) {
    return 'Dịch vụ TikTok trả về mã $status. Hãy thử lại sau ít phút.';
  }

  @override
  String tiktokConnectionFailed(String error) {
    return 'Không kết nối được dịch vụ TikTok: $error';
  }

  @override
  String get tiktokInvalidData =>
      'Không đọc được dữ liệu video TikTok. Liên kết có thể đã bị xóa hoặc chuyển sang riêng tư.';

  @override
  String get noWatermark => 'Không logo';

  @override
  String get withWatermark => 'Có logo TikTok';

  @override
  String get originalSound => 'Nhạc gốc';

  @override
  String audioMp3Label(String title) {
    return 'Âm thanh MP3 ($title)';
  }

  @override
  String get tiktokNoStreams =>
      'TikTok không trả về luồng tải nào cho video này.';

  @override
  String get instagramInvalidPost =>
      'Không nhận diện được link Instagram. Hãy dùng link bài đăng, reel, story hoặc highlight.';

  @override
  String get instagramLoginRequired =>
      'Instagram yêu cầu đăng nhập để xem bài đăng này. Chỉ Reels và video công khai mới tải được.';

  @override
  String linkAccessFailed(String error) {
    return 'Không truy cập được liên kết: $error';
  }

  @override
  String get directMediaLink => 'Liên kết media trực tiếp';

  @override
  String get originalAudio => 'Âm thanh (Gốc)';

  @override
  String get originalVideo => 'Video (Gốc)';

  @override
  String get genericNoVideo =>
      'Không tìm thấy video tại liên kết này. Hãy kiểm tra URL hoặc dán liên kết trực tiếp tới file .mp4.';

  @override
  String get embeddedVideo => 'Video nhúng (Web)';

  @override
  String get facebookNoVideo =>
      'Không lấy được nội dung từ bài Facebook này. Hãy đảm bảo bài viết ở chế độ công khai; bài riêng tư và nhóm kín cần đăng nhập.';

  @override
  String get highQuality720 => 'HD 720p (Chất lượng cao)';

  @override
  String get standardQuality480 => 'SD 480p (Tiêu chuẩn)';

  @override
  String get invalidVideoUrl =>
      'Vui lòng nhập URL video hợp lệ sử dụng http hoặc https.';

  @override
  String get unableToAnalyze => 'Không thể phân tích liên kết này.';

  @override
  String get externalServicesDisabled =>
      'Dịch vụ trích xuất bên ngoài đang bị tắt trong Cài đặt. Hãy bật để tải bài này.';

  @override
  String get galleryMayBeIncomplete =>
      'Chỉ đọc được ảnh bìa. Bật dịch vụ bên ngoài trong Cài đặt để tìm nốt những ảnh còn lại.';

  @override
  String get galleryCheckUnavailable =>
      'Chỉ đọc được ảnh bìa, và dịch vụ liệt kê các ảnh còn lại không phản hồi. Bài này có thể còn ảnh khác.';
}
