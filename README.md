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
  - **Tạm dừng & tiếp tục**: giữ lại phần đã tải và nối tiếp bằng HTTP Range
    (tự động tải lại từ đầu nếu máy chủ không hỗ trợ Range).
  - Hủy tiến trình tải và dọn sạch các mục đã xong.
  - **Thử lại thông minh**: tự động phân tích lại link gốc để lấy URL mới, vì
    link tải của YouTube / Facebook / Instagram có chữ ký hết hạn theo thời gian.
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
│       ├── cors_helper.dart         # Bọc URL qua proxy CORS khi chạy trên Web
│       ├── formatters.dart          # Định dạng dung lượng bytes, thời lượng, số đếm
│       ├── http_helper.dart         # HTTP dùng chung cho extractor (header, timeout, proxy)
│       ├── json_scanner.dart        # Cắt object JSON cân bằng ngoặc từ HTML
│       ├── local_video_source.dart  # Tạo controller phát file cục bộ (native / web)
│       ├── platform_file.dart       # Thao tác file & thư viện ảnh (native / web)
│       ├── quality_helper.dart      # Xếp hạng & chọn chất lượng theo pixel height
│       ├── text_unescape.dart       # Giải mã escape JSON (\uXXXX) và HTML entity
│       ├── url_helper.dart          # Lọc URL, nhận diện nền tảng theo host
│       └── web_download_helper.dart # Kích hoạt tải file trên trình duyệt
├── models/
│   ├── download_task.dart           # Model quản lý trạng thái tải về
│   ├── video_metadata.dart          # Model thông tin video & chất lượng
│   └── video_platform.dart          # Enum nền tảng (YouTube, TikTok, FB, X,...)
├── services/
│   ├── download_service.dart        # Tiến trình tải luồng bằng Dio
│   ├── storage_service.dart         # Lưu trữ file cục bộ & Gal (Thư viện ảnh)
│   └── extractors/
│       ├── base_extractor.dart      # Interface cơ sở + ExtractionException
│       ├── facebook_extractor.dart  # Facebook & Reels (watch page → embed → m.facebook)
│       ├── generic_extractor.dart   # Link trực tiếp & video nhúng qua Open Graph
│       ├── instagram_extractor.dart # Instagram Reels & video bài viết công khai
│       ├── registry.dart            # Quản lý & điều phối bộ bóc tách
│       ├── tiktok_extractor.dart    # TikTok không watermark (HD) + nhạc gốc MP3
│       ├── twitter_extractor.dart   # X / Twitter (FxTwitter → VxTwitter)
│       └── youtube_extractor.dart   # YouTube: YoutubeExplode (native) / watch page (web)
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

server.js                            # Web dev server: phục vụ build/web + CORS proxy
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

   Kiểm thử trên thiết bị Android thật/emulator (storage, tải file, tạm dừng &
   tiếp tục, lưu vào thư viện ảnh) — cần chạy fixture server trên máy host trước:
   ```bash
   node tool/fixture_server.js          # cửa sổ riêng
   flutter test integration_test/android_storage_test.dart -d <device-id>
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

## 🌐 Chạy bản Web (kèm CORS proxy)

Trình duyệt chặn request cross-origin tới YouTube/TikTok/Facebook, nên bản Web
phải đi qua proxy cục bộ trong `server.js`.

```bash
flutter build web --release
node server.js          # http://127.0.0.1:8080
```

Cấu hình qua biến môi trường: `PORT` (mặc định `8080`) và `HOST` (mặc định
`127.0.0.1`).

Proxy cung cấp 2 endpoint:

| Endpoint | Công dụng |
|---|---|
| `GET/POST /cors-proxy?url=<url>` | Chuyển tiếp request, forward `Range` để tua video. Thêm `&filename=<tên>` để trả `Content-Disposition: attachment` — đây là cách duy nhất trình duyệt lưu được video cross-origin. |
| `GET /resolve?url=<url>` | Theo redirect phía server và trả về URL cuối, dùng để mở rộng link rút gọn (`t.co`, `fb.watch`, `vm.tiktok.com`). |

**Bảo mật:** proxy chỉ bind loopback, chỉ chấp nhận `http`/`https` trên cổng
80/443, và từ chối mọi hostname phân giải ra địa chỉ loopback / private /
link-local (chặn SSRF tới dịch vụ nội bộ và endpoint metadata của cloud). Mỗi
bước redirect đều được kiểm tra lại. Phần phục vụ file tĩnh chỉ đọc trong
`build/web`.

> ⚠️ Bản Web chỉ tải được video có luồng công khai. Video YouTube dùng
> `signatureCipher` cần giải mã bằng JS của YouTube — hãy dùng bản Android /
> iOS / Desktop cho những video đó.

---

## 📱 Cấu hình quyền (Permissions)

### Android (`android/app/src/main/AndroidManifest.xml`):
- `INTERNET` & `ACCESS_NETWORK_STATE`
- `WRITE_EXTERNAL_STORAGE` chỉ tới Android 10 (API 29), theo yêu cầu của `gal`
  khi xuất file vào thư viện trên thiết bị cũ. Android 11+ dùng MediaStore và
  không yêu cầu quyền đọc ảnh/video của người dùng.
- HTTP thường bị tắt mặc định qua `res/xml/network_security_config.xml`; chỉ vài
  CDN video còn phục vụ cleartext mới được mở riêng, thay vì bật
  `usesCleartextTraffic` cho toàn ứng dụng.
- **Không dùng `requestLegacyExternalStorage`**: app ghi file vào thư mục external
  riêng của chính nó (`Android/data/<package>/files/SnapVideos`) và đưa video vào
  thư viện ảnh qua MediaStore (`gal`). Cả hai đều tuân thủ scoped storage, nên
  không cần chế độ lưu trữ cũ (chế độ này cũng bị Android 11+ bỏ qua).

### iOS (`ios/Runner/Info.plist`):
- `NSPhotoLibraryUsageDescription`
- `NSPhotoLibraryAddUsageDescription`
- `NSAppTransportSecurity` (Allows Arbitrary Loads cho video streams)

---

## 📄 Bản quyền

Dự án được xây dựng phục vụ mục đích học tập và chia sẻ mã nguồn mã nguồn mở.
Repository: [https://github.com/vannt-dev/snap-video](https://github.com/vannt-dev/snap-video)
