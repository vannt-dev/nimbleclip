# 🚀 SnapVideo - Multi-Platform Video & Audio Downloader

Ứng dụng Flutter hiện đại, mượt mà hỗ trợ tải video chất lượng cao (HD 1080p, 720p, 480p) và trích xuất âm thanh MP3 từ các nền tảng phổ biến: **YouTube, TikTok (Không Watermark), Facebook, Twitter / X, Instagram** và nhiều liên kết trực tiếp khác.

---

## 🌟 Tính năng nổi bật

- **Đa nền tảng hỗ trợ**:
  - 🎬 **YouTube**: Tải video các độ phân giải (1080p, 720p, 480p, 360p) và tách nhạc MP3/M4A chất lượng 320kbps thông qua thư viện xử lý trực tiếp.
  - 🎵 **TikTok**: Tự động lấy video chất lượng Full HD không logo / không dính watermark (No Watermark) và trích xuất âm thanh gốc.
  - 📘 **Facebook**: Hỗ trợ video HD, Reels, Watch và video công khai.
  - 🐦 **Twitter / X**: Hỗ trợ tất cả độ phân giải và bitrate cao nhất từ tweet video.
  - 📷 **Instagram**: Hỗ trợ Reels và video bài viết.
  - 🔗 **Direct Links**: Hỗ trợ tải các liên kết video trực tiếp (.mp4, .webm, .mkv,...).
- **Tự động nhận diện Clipboard**: Tự động phát hiện liên kết video khi vừa sao chép và mở ứng dụng.
- **Trình phát Video tích hợp (In-App Player)**: Xem trước video trước khi tải về hoặc phát các video đã tải trực tiếp trong app với đầy đủ điều khiển tua, phóng to toàn màn hình.
- **Quản lý tải về thông minh (Download Manager)**:
  - Hiển thị phần trăm tiến trình thời gian thực.
  - Hiển thị tốc độ tải (MB/s, KB/s) và dung lượng đã nhận / tổng dung lượng.
  - Hỗ trợ hủy tiến trình tải.
- **Lưu trực tiếp vào Thư viện ảnh (Gallery/Album)**: Tự động hoặc thủ công lưu video đã tải vào ứng dụng Photos của thiết bị Android & iOS.
- **Chia sẻ & Mở file**: Chia sẻ video nhanh chóng qua Zalo, Messenger, Telegram,... hoặc mở bằng trình phát mặc định của máy.
- **Giao diện hiện đại & Tùy biến**:
  - Hỗ trợ Dark Mode (Giao diện tối sang trọng) và Light Mode (Giao diện sáng).
  - Quản lý bộ nhớ và dung lượng cache video đã tải.

---

## 🏗️ Cấu trúc dự án

```
lib/
├── core/
│   ├── constants/
│   │   ├── app_colors.dart          # Bảng màu thương hiệu & hệ thống giao diện
│   │   └── app_constants.dart       # Cấu hình hằng số & storage keys
│   ├── theme/
│   │   └── app_theme.dart           # Cấu hình Material 3 Light & Dark Theme
│   └── utils/
│       ├── formatters.dart          # Định dạng dung lượng bytes, thời lượng, số đếm
│       └── url_helper.dart          # Lọc URL, nhận diện nền tảng video
├── models/
│   ├── download_task.dart           # Model quản lý trạng thái tải về
│   ├── video_metadata.dart          # Model thông tin video & chất lượng
│   └── video_platform.dart          # Enum nền tảng (YouTube, TikTok, FB, X,...)
├── services/
│   ├── download_service.dart        # Tiến trình tải luồng bằng Dio
│   ├── storage_service.dart         # Lưu trữ file cục bộ & Gal (Thư viện ảnh)
│   └── extractors/
│       ├── base_extractor.dart      # Interface cơ sở cho bộ bóc tách link
│       ├── facebook_extractor.dart  # Bóc tách video Facebook & Reels
│       ├── generic_extractor.dart   # Bóc tách link trực tiếp & Web Video
│       ├── registry.dart            # Quản lý & điều phối bộ bóc tách
│       ├── tiktok_extractor.dart    # Bóc tách TikTok Không Watermark (HD)
│       ├── twitter_extractor.dart   # Bóc tách video X / Twitter
│       └── youtube_extractor.dart   # Bóc tách video YouTube bằng YoutubeExplode
├── providers/
│   ├── download_provider.dart       # Quản lý danh sách & trạng thái tải về
│   ├── settings_provider.dart       # Quản lý cài đặt giao diện, cache, clipboard
│   └── video_extractor_provider.dart# Quản lý trạng thái phân tích link video
├── views/
│   ├── home/                        # Màn hình chính (Dán link, phân tích, chọn chất lượng)
│   ├── downloads/                   # Màn hình quản lý video đang tải và đã tải
│   ├── player/                      # Trình phát video trong ứng dụng
│   ├── settings/                    # Màn hình cài đặt & quản lý bộ nhớ
│   └── main_navigation_screen.dart  # Thanh điều hướng chính (Bottom Navigation)
└── main.dart                        # Điểm khởi chạy ứng dụng (MultiProvider)
```

---

## 🚀 Hướng dẫn cài đặt & Chạy ứng dụng

### Yêu cầu hệ thống:
- Flutter SDK `>= 3.12.0` (khuyến nghị Flutter 3.22 trở lên)
- Dart SDK `^3.12.2`
- Android Studio / VS Code / Xcode (nếu chạy trên macOS/iOS)

### Các bước chạy:

1. **Clone repository**:
   ```bash
   git clone https://github.com/vannt-dev/snap-video.git
   cd snap-video
   ```

2. **Cài đặt các gói phụ thuộc (Dependencies)**:
   ```bash
   flutter pub get
   ```

3. **Chạy kiểm tra mã nguồn**:
   ```bash
   flutter analyze
   flutter test
   ```

4. **Khởi chạy ứng dụng**:
   - Chạy trên thiết bị Android hoặc máy ảo:
     ```bash
     flutter run
     ```
   - Chạy trên thiết bị iOS (trên macOS):
     ```bash
     flutter run -d ios
     ```
   - Chạy trên Windows:
     ```bash
     flutter run -d windows
     ```

---

## 📱 Cấu hình quyền (Permissions)

### Android (`android/app/src/main/AndroidManifest.xml`):
- `INTERNET` & `ACCESS_NETWORK_STATE`
- `READ_EXTERNAL_STORAGE` & `WRITE_EXTERNAL_STORAGE`
- `READ_MEDIA_VIDEO`, `READ_MEDIA_IMAGES`, `READ_MEDIA_AUDIO` (Hỗ trợ Android 13+)

### iOS (`ios/Runner/Info.plist`):
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- `NSAppTransportSecurity` (Allows Arbitrary Loads cho video streams)

---

## 📄 Bản quyền

Dự án được xây dựng phục vụ mục đích học tập và chia sẻ mã nguồn mã nguồn mở.
Repository: [https://github.com/vannt-dev/snap-video](https://github.com/vannt-dev/snap-video)
