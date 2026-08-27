# NimbleClip

[![CI](https://github.com/vannt-dev/nimbleclip/actions/workflows/ci.yml/badge.svg)](https://github.com/vannt-dev/nimbleclip/actions/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.x-0175C2?logo=dart)](https://dart.dev/)

**Save clips. Keep moments.**

NimbleClip is a Flutter application for discovering and downloading publicly
available video, audio, and image posts from popular social platforms. It provides a
single, polished interface for link detection, quality selection, download
management, local playback, and gallery export.

> NimbleClip is intended for content you own, content in the public domain, or
> content you are authorized to download. You are responsible for complying
> with the source platform's terms and applicable copyright laws.

## Features

- Detects supported links pasted from the clipboard.
- Accepts links shared directly from other apps on Android and iOS, and
  registers an Android Direct Share target so it appears in the top row of the
  share sheet.
- Analyzes multiple pasted/shared links in one pass, queues their best media
  options together, and keeps the latest 20 analyzed links locally.
- Limits batch analysis to 20 links with three concurrent extractors, while
  allowing per-link quality selection, retry, and cancellation.
- Parses large posts on a background isolate, so the interface keeps responding
  while a link whose page embeds megabytes of inline data is analyzed.
- Extracts available video, audio, and image options before downloading.
- Shows carousel thumbnails in a lazy full-screen picker, with preview,
  select-all, and multi-image download for supported Facebook, Instagram,
  TikTok, and X posts.
- Uses one shared download queue with a configurable limit of one to five
  concurrent transfers, so separate batches cannot overload the device or
  network.
- Prevents the same source option from being queued twice while it is already
  downloading, and asks for confirmation before downloading an existing
  completed file again.
- Tracks progress, transfer speed, and downloaded file size per task without
  rebuilding the entire download list.
- Runs mobile downloads through Android DownloadWorker and iOS URLSession with
  progress notifications, retry, pause, and resume while the app is in the
  background.
- Recovers queued and running native transfers after the app process is
  terminated, then reconnects them to the in-app download history.
- Refreshes expired media URLs before retrying a failed download.
- Uses compact, filesystem-safe, platform-prefixed UUID filenames such as
  `facebook_<uuid>` and `x_<uuid>`, and validates downloaded media from its
  actual file signature. Native video downloads are also opened by the platform
  player once before they are marked complete, preventing an HTML error page or
  broken video from appearing as a successful download.
- Previews remote media and plays downloaded files inside the app. Previews are
  decoded at the size the screen can show, with headroom for zoom, so a
  full-resolution post photo never has to fit in memory at its native size.
- Saves completed videos and images to the device gallery on Android and iOS;
  audio remains available from NimbleClip's download directory.
- Keeps the Android MediaStore URI after Gallery export so media can still be
  opened or shared when the app-local cache copy is removed. Safe cache cleanup
  after Gallery export is enabled by default and can be changed in Settings.
- Opens or shares downloaded files with other installed applications, reports
  missing handlers and operation failures, and reconciles history when a local
  file has been removed outside the app.
- Persists download history and user preferences locally.
- Stores analysis history without expiring signed media URLs and provides
  copyable extraction diagnostics with timing and app-version context.
- Lets users disable external extraction services. Some TikTok and X downloads,
  plus carousel fallbacks for Facebook and Instagram, require these services
  and may send the public post URL to them.
- Supports light, dark, and system themes.
- Supports English and Vietnamese, with automatic device-locale detection and
  a persisted in-app language preference.
- Includes a browser build backed by a local, SSRF-hardened CORS proxy.

## Supported sources

| Source | Supported content |
| --- | --- |
| YouTube | Public videos and available M4A audio streams |
| TikTok | Public videos, slideshows/image posts, including watermark-free variants when exposed by the source, and audio |
| Facebook | Public videos, Watch links, Reels, image posts, carousels, and mixed-media posts |
| X / Twitter | Public posts containing images, videos, or mixed media |
| Instagram | Public image/carousel posts, video posts, Reels, and mixed-media posts |
| Direct URLs | Public image, video, or audio files and pages exposing standard Open Graph media metadata |

Extraction depends on public endpoints and page formats controlled by third
parties. A platform change, regional restriction, authentication requirement,
DRM protection, or expired signature may prevent a specific link from working.

## Platform support

The repository contains Flutter targets for Android, iOS, Windows, macOS,
Linux, and Web. Native targets provide the complete download workflow. The Web
target has browser-specific limitations and requires the included Node.js
server for cross-origin requests and downloads.

## Languages

- English (`en`)
- Vietnamese (`vi`)
- System default, with English used for unsupported device locales

Translations are maintained as ARB files in `lib/l10n`. Flutter generates the
typed localization API from these resources during dependency resolution and
builds.

## Getting started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) on the stable channel
- A platform toolchain for the target you want to run:
  - Android Studio and an Android SDK for Android
  - Xcode on macOS for iOS and macOS
  - Visual Studio with Desktop development with C++ for Windows
  - Windows Developer Mode enabled when building the Windows target, because
    Flutter plugins require symbolic-link support
  - The Flutter Linux desktop prerequisites for Linux
- Node.js 22 or later when running the Web build or server tests

The exact Dart SDK constraint is defined in `pubspec.yaml`.

### Install

```bash
git clone https://github.com/vannt-dev/nimbleclip.git
cd nimbleclip
flutter pub get
git config core.hooksPath .githooks
```

The repository hooks enforce Conventional Commits, run formatting and static
analysis before commits, and run tests plus a release Web build before pushes.
Run `tool/check.sh all` at any time to execute the platform-independent local
gates. On Windows, the all-in-one command below also manages the emulator,
fixture server, and Android integration suite.

### Verify the project

One command runs formatting, static analysis, Flutter and Node tests, a release
Web build, and the Android integration suite. It reuses or starts the configured
emulator and shuts down the temporary fixture server when finished:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\check_all.ps1
```

Use `-SkipAndroid` for the faster platform-independent gates, or
`-SkipWebBuild` when a Web bundle is not needed.

Live extractor smoke tests are kept opt-in because public posts can be removed
or made private without notice. The default suite checks known public Facebook,
X, and TikTok image/video posts:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\check_live_extractors.ps1
```

Pass current public Instagram examples when validating Instagram as well:

```powershell
.\tool\check_live_extractors.ps1 `
  -InstagramImageUrl <public-carousel-url> `
  -InstagramVideoUrl <public-reel-url>
```

The same live suite can be included in the all-in-one workflow with
`-RunLiveExtractors` and the corresponding Instagram URL parameters.

The equivalent individual commands are:

```bash
flutter analyze
flutter test
node --check server.js
node --test test/server_test.js
```

### Run the app

List the available targets:

```bash
flutter devices
```

Then launch NimbleClip on a selected target:

```bash
flutter run -d <device-id>
```

Examples:

```bash
flutter run -d windows
flutter run -d chrome
```

On Windows, the repository provides a one-command Android emulator launcher.
It reuses or starts the configured emulator, closes an old NimbleClip instance,
and runs the app without repeating dependency checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\run_android_emulator.ps1
```

AI coding agents should follow the shorter workflow documented in
[`AGENTS.md`](AGENTS.md) instead of probing devices before every launch.

### Regenerate branded app icons

The master artwork lives at `assets/branding/nimbleclip_icon_master.png`.
After replacing it, regenerate the Android, iOS, Web, macOS, Windows, adaptive,
round, themed, and splash assets with:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\generate_app_icons.ps1
```

## Android integration test

The Android storage test uses a fixture server running on the host machine.
Start it in a separate terminal before running the test on a device or emulator:

```bash
node tool/fixture_server.js
```

```bash
flutter test integration_test/android_storage_test.dart -d <device-id>
```

The fixture exposes `GET /health` on port `8097`. The all-in-one verification
script checks this identity before reusing the port, so an unrelated local
process cannot be mistaken for the test server.

The suite covers scoped storage, file integrity, playable video validation,
cleartext development-host access, clean and resumed downloads, servers that
ignore or change range behavior, Gallery/MediaStore export and URI lookup, and
cache cleanup. The same suite runs on an Android emulator in CI.

## Web build

Browsers block many cross-origin media requests made directly to social
platforms. NimbleClip's Web build therefore uses the local proxy in `server.js`.

```bash
flutter build web --release
node server.js
```

Open `http://127.0.0.1:8080` by default. The server accepts two optional
environment variables:

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOST` | `127.0.0.1` | Address used by the local server |
| `PORT` | `8080` | HTTP port used by the local server |

### Proxy endpoints

| Endpoint | Purpose |
| --- | --- |
| `GET/POST/HEAD /cors-proxy?url=<url>` | Proxies an HTTP request and forwards range headers for media seeking. Add `filename=<name>` to return a download response. |
| `GET /resolve?url=<url>` | Resolves redirects for shortened links such as `t.co`, `fb.watch`, and `vm.tiktok.com`. |
| `POST /youtube-decipher` | Deciphers YouTube `signatureCipher` and throttling parameters for the Web extractor using a restricted transform parser. |

The proxy only accepts HTTP and HTTPS destinations on ports 80 and 443. It
validates every redirect and rejects loopback, private, link-local, and other
non-public destination addresses to reduce SSRF risk. Static files are served
only from `build/web`. Every route also enforces an explicit HTTP method
allowlist; unsupported methods return `405 Method Not Allowed`.

The YouTube Web fallback parses only supported array transform operations and
never evaluates the remote player JavaScript. YouTube can still reject private,
age-restricted, DRM-protected, or region-restricted content.

## Build artifacts

```bash
# Android APK
flutter build apk --release

# Android App Bundle
flutter build appbundle --release

# Web
flutter build web --release

# Windows, macOS, or Linux (run on the matching host OS)
flutter build windows
flutter build macos
flutter build linux
```

Run `flutter clean` first if the Android integration suite ran in the same
checkout. That suite leaves `integration_test` in the generated plugin
registrant, and the release build then fails with `package
dev.flutter.plugins.integration_test does not exist`.

Release builds may require platform-specific signing configuration before they
can be distributed through an app store.

## Project structure

```text
lib/
|-- core/
|   |-- constants/       App-wide values and storage keys
|   |-- theme/           Material themes and colors
|   `-- utils/           URL, HTTP, parsing, quality, image, and file helpers
|-- models/              Video metadata and download task models
|-- providers/           Application state and workflow coordination
|-- services/
|   |-- extractors/      Extractors, page parsers, fallback clients, registry
|   |-- async_work_queue.dart
|   |-- background_download_service.dart
|   |-- download_history_repository.dart
|   |-- download_service.dart
|   |-- media_file_actions.dart
|   `-- storage_service.dart
|-- views/               Home, downloads, player, and settings screens
`-- main.dart            Application entry point

integration_test/        Device-level Android storage tests
test/                    Flutter unit, widget, fixture, and Node server tests
tool/                    Quality checks, fixture server, emulator launcher,
                         icon generator, and release/signing helpers
server.js                Web static server, URL resolver, and CORS proxy
```

The extractor registry and external-service privacy policy are injected at the
application boundary, so tests and providers do not depend on mutable global
state. Extractors coordinate platform strategies while dedicated parsers and
fallback clients handle response interpretation and third-party HTTP calls.
Page scans that have to decode and walk a post's inline JSON move to a
background isolate once the document is large enough to be worth the hand-off,
and run inline below that threshold and on the Web, where the browser offers no
second isolate.

The download provider coordinates the workflow but delegates transfer work,
global concurrency, persistent history, and platform file actions to separate
services. Shared media-format, URL, quality, and selection helpers keep image,
video, and audio behavior consistent across platforms and screens.

## Storage and permissions

### Android

- `INTERNET` and `ACCESS_NETWORK_STATE` are required for extraction and
  downloads.
- `WRITE_EXTERNAL_STORAGE` is limited to Android 10 and earlier for legacy
  gallery export support.
- Android 11 and later use scoped storage and MediaStore.
- Active files are stored under the app-specific external directory at
  `Android/data/com.vannt.nimbleclip/files/NimbleClip` before optional gallery
  export.
- Cleartext HTTP is disabled by default and only explicitly allowed for the
  small set of media CDNs declared in the network security configuration.

### iOS

NimbleClip declares photo-library usage descriptions for saving downloaded
media. App Transport Security exceptions are configured for remote media
streams that do not support the default policy.

## Continuous integration

The GitHub Actions workflow runs on every pull request and every push to
`main`. It validates commit messages and formatting, performs Flutter static
analysis and tests, builds an Android APK and release Web bundle, runs the Node
server checks, builds iOS with the Share Extension and App Group checks, and
executes the Android storage/download integration suite on an API 34 emulator.
A version-bump commit on `main` automatically starts the signed release
workflow after every CI job succeeds, as documented in
[RELEASING.md](RELEASING.md).

## Contributing

Issues and pull requests are welcome. Before submitting a change, run:

```bash
tool/check.sh all
```

Use a Conventional Commit subject such as `fix(web): reject unsafe redirects`.

Keep extractor changes focused and include a sanitized fixture test whenever a
third-party response format is involved. Never commit authentication tokens,
cookies, private media, or personal account data.

## Disclaimer

NimbleClip is not affiliated with, endorsed by, or sponsored by YouTube,
TikTok, Meta, Instagram, Facebook, or X. Product names and trademarks belong to
their respective owners.
