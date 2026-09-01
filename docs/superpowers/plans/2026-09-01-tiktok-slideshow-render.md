# TikTok Slideshow Render Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn a TikTok photo post's images and music into one downloadable MP4, rendered on the device.

**Architecture:** The extractor emits an extra `VideoQualityOption` carrying a `SlideshowSource` instead of a URL. Dart fetches the images and the music to a temp directory, then hands local file paths to an Android `MethodChannel` whose Kotlin side decodes, composites onto a 1080×1920 canvas, encodes H.264 with `MediaCodec`, and muxes with `MediaMuxer`. iOS and Web get a stub renderer that reports itself unsupported, and the option is hidden there.

**Tech Stack:** Flutter/Dart 3.12, Kotlin, Android `MediaCodec` / `MediaMuxer` / `MediaExtractor`, `path_provider`, existing `ExtractorHttp`.

**Spec:** `docs/superpowers/specs/2026-09-01-tiktok-slideshow-render-design.md`

## Global Constraints

- **No existing test may be edited.** The baseline is 222 passing + 8 skipped. If a change forces an edit to an existing expectation, stop and redesign — that is a regression signal, not a test to update.
- **Shared code is extended, never rewritten.** New branches are added ahead of existing bodies; existing bodies stay byte-identical.
- `MediaKind` must not gain a value. `MediaFileValidator` and `DownloadTask.fromJson` both consume it and neither has a notion of a slideshow.
- `VideoQualityOption.downloadUrl` stays non-nullable. The slideshow option sets it to `''` and is fenced by an assert plus a guard test.
- Nothing under `lib/services/`, `lib/models/`, or `lib/core/` may import `views/`, `providers/`, or `app_localizations` — `test/architecture_test.dart` enforces this.
- Commits follow Conventional Commits (`.githooks/commit-msg`). **No `Co-Authored-By` trailer.**
- Canvas 1080×1920, 30fps, 3s per image. Clip length is the shorter of the image run and the music track.
- Full verification is one command: `powershell -ExecutionPolicy Bypass -File .\tool\check_all.ps1`. Use `-SkipAndroid` for Dart-only tasks.

---

### Task 1: Lock the current behaviour before touching anything

Pure test task. Adds no production code. These tests must still pass, unedited, at the end of every later task — they are the proof that the finished flows did not move.

**Files:**
- Test: `test/slideshow_baseline_test.dart` (create)

**Interfaces:**
- Consumes: nothing
- Produces: nothing; a safety net only

- [ ] **Step 1: Write the characterisation tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/core/utils/quality_helper.dart';
import 'package:nimble_clip/services/extractors/tiktok_extractor.dart';

import 'extractor_fixture_test.dart' show fixture;

/// The behaviour a TikTok photo post has today, recorded so the slideshow
/// feature can prove it did not change it.
void main() {
  tearDown(ExtractorHttp.resetOverrides);

  Future<void> withPhotoPost(void Function(dynamic result) check) async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);
    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
    );
    check(result);
  }

  test('a photo post still defaults to an image, not a video', () async {
    await withPhotoPost((result) {
      expect(QualityHelper.bestMatch(result.qualities, 'Highest')!.isImage,
          isTrue);
      expect(result.bestQuality!.isImage, isTrue);
    });
  });

  test('a photo post still lists its images in source order', () async {
    await withPhotoPost((result) {
      final images =
          result.qualities.where((o) => o.isImage).toList();
      expect(images, hasLength(2));
      expect(images.first.downloadUrl, endsWith('/tiktok/image-1.jpg'));
      expect(images.last.downloadUrl, endsWith('/images/image-2.webp'));
    });
  });

  test('a photo post still exposes exactly one audio option', () async {
    await withPhotoPost((result) {
      expect(result.qualities.where((o) => o.isAudioOnly), hasLength(1));
    });
  });
}
```

- [ ] **Step 2: Run them and confirm they pass against today's code**

Run: `flutter test test/slideshow_baseline_test.dart`
Expected: PASS, 3 tests. If any fails, the baseline assumption is wrong — stop and report before continuing.

- [ ] **Step 3: Commit**

```bash
git add test/slideshow_baseline_test.dart
git commit -m "test(tiktok): record how a photo post behaves before slideshows"
```

---

### Task 2: The `SlideshowVideo` quality descriptor

**Files:**
- Modify: `lib/models/quality_descriptor.dart`
- Modify: `lib/l10n/quality_descriptor_text.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_vi.arb`
- Test: `test/quality_descriptor_text_test.dart` (add cases; do not edit existing ones)

**Interfaces:**
- Produces: `class SlideshowVideo extends QualityDescriptor { const SlideshowVideo(this.imageCount); final int imageCount; }`, token `slideshow:<n>`, l10n key `slideshowLabel(int count)`

- [ ] **Step 1: Write the failing tests**

Append to `test/quality_descriptor_text_test.dart`:

```dart
  test('a slideshow descriptor names itself with its image count', () {
    expect(
      describeQuality(const SlideshowVideo(5), enL10n),
      'Slideshow video (5 images)',
    );
  });

  test('a slideshow descriptor round-trips through its token', () {
    expect(qualityDescriptorToken(const SlideshowVideo(5)), 'slideshow:5');
  });
```

Use whatever helper the existing file already uses to obtain `enL10n`; do not introduce a second one.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/quality_descriptor_text_test.dart`
Expected: FAIL — `SlideshowVideo` is not defined.

- [ ] **Step 3: Add the descriptor**

In `lib/models/quality_descriptor.dart`, after `WatermarkedVideo`:

```dart
/// A video that does not exist yet: it is rendered on the device from the
/// post's own images. [imageCount] is what tells the reader how long it will
/// be before anything plays.
class SlideshowVideo extends QualityDescriptor {
  const SlideshowVideo(this.imageCount);
  final int imageCount;
}
```

Add to `qualityDescriptorToken`'s switch, beside the other variants:

```dart
    SlideshowVideo(:final imageCount) => 'slideshow:$imageCount',
```

- [ ] **Step 4: Add the strings**

`lib/l10n/app_en.arb`:

```json
  "slideshowLabel": "Slideshow video ({count} images)",
  "@slideshowLabel": {
    "description": "A video rendered on the device from a photo post's images",
    "placeholders": { "count": { "type": "int" } }
  },
```

`lib/l10n/app_vi.arb`:

```json
  "slideshowLabel": "Video từ ảnh ({count} ảnh)",
```

- [ ] **Step 5: Render it**

In `lib/l10n/quality_descriptor_text.dart`'s switch:

```dart
    SlideshowVideo(:final imageCount) => l10n.slideshowLabel(imageCount),
```

The switch is exhaustive over a sealed hierarchy, so omitting this is a compile error, not a blank row.

- [ ] **Step 6: Run to verify pass**

Run: `flutter gen-l10n && flutter test test/quality_descriptor_text_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/models/quality_descriptor.dart lib/l10n/ test/quality_descriptor_text_test.dart
git commit -m "feat(models): describe a device-rendered slideshow option"
```

---

### Task 3: `SlideshowSource` and the option field

**Files:**
- Create: `lib/models/slideshow_source.dart`
- Modify: `lib/models/video_metadata.dart`
- Test: `test/slideshow_source_test.dart` (create)

**Interfaces:**
- Consumes: `SlideshowVideo` from Task 2
- Produces: `SlideshowSource({required List<String> imageUrls, String? audioUrl, Duration perImage, int width, int height})`, `VideoQualityOption.slideshow(...)`, `bool get needsRendering`

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/quality_descriptor.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/models/video_metadata.dart';

void main() {
  const source = SlideshowSource(
    imageUrls: ['https://cdn/1.jpg', 'https://cdn/2.jpg'],
    audioUrl: 'https://cdn/song.mp3',
  );

  test('a slideshow option needs rendering and carries no download url', () {
    const option = VideoQualityOption.slideshow(
      id: 'tt_slideshow_1',
      label: SlideshowVideo(2),
      source: source,
    );
    expect(option.needsRendering, isTrue);
    expect(option.downloadUrl, isEmpty);
    // It produces a video, so it stays in the video tab's kind.
    expect(option.kind, MediaKind.video);
  });

  test('an ordinary option does not need rendering', () {
    const option = VideoQualityOption.video(
      id: 'v',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn/v.mp4',
    );
    expect(option.needsRendering, isFalse);
  });

  test('the default timing is three seconds an image at 1080x1920', () {
    expect(source.perImage, const Duration(seconds: 3));
    expect(source.width, 1080);
    expect(source.height, 1920);
  });

  test('an option with neither a url nor a source is rejected', () {
    expect(
      () => VideoQualityOption(
        id: 'x',
        label: const OriginalMp4(),
        quality: '720p',
        format: 'mp4',
        downloadUrl: '',
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/slideshow_source_test.dart`
Expected: FAIL — `slideshow_source.dart` does not exist.

- [ ] **Step 3: Write the model**

`lib/models/slideshow_source.dart`:

```dart
/// What the device needs in order to render a photo post into one video.
///
/// Carries URLs rather than files: fetching belongs to the service layer,
/// which already owns the headers, the retry policy and the privacy switch.
class SlideshowSource {
  const SlideshowSource({
    required this.imageUrls,
    this.audioUrl,
    this.perImage = const Duration(seconds: 3),
    this.width = 1080,
    this.height = 1920,
  });

  final List<String> imageUrls;

  /// Null when the post carried no music, or when the track cannot be used.
  final String? audioUrl;

  final Duration perImage;
  final int width;
  final int height;

  Duration get totalDuration => perImage * imageUrls.length;
}
```

- [ ] **Step 4: Add the field and the constructor**

In `lib/models/video_metadata.dart`, import `slideshow_source.dart`, add the field beside `mediaId`:

```dart
  /// Set only on an option that must be rendered on the device before there
  /// is a file. Null for everything that is fetched from a URL.
  final SlideshowSource? slideshow;

  bool get needsRendering => slideshow != null;
```

Add `this.slideshow` to every existing constructor's parameter list as an optional named parameter defaulting to null, and add the assert to the base constructor:

```dart
  const VideoQualityOption({
    ...
    this.slideshow,
  }) : assert(
         downloadUrl != '' || slideshow != null,
         'An option with no download URL must carry a SlideshowSource.',
       );
```

Add the dedicated constructor:

```dart
  /// A video the device will render from [source]. [downloadUrl] is empty
  /// because there is nothing to fetch; `needsRendering` is what callers
  /// branch on.
  const VideoQualityOption.slideshow({
    required this.id,
    required this.label,
    required SlideshowSource source,
    this.quality = 'Slideshow',
    this.format = 'mp4',
    this.thumbnailUrl,
    this.mediaId,
  }) : kind = MediaKind.video,
       downloadUrl = '',
       sizeBytes = null,
       headers = null,
       slideshow = source;
```

`toJson` and `fromJson` stay as they are: the option is never persisted — it is rendered, and what reaches history is the finished file.

**Watch the assert against `fromJson`.** `VideoQualityOption.fromJson` calls the base constructor with `json['downloadUrl'] as String? ?? ''`, so a stored payload that has no URL — a legacy or truncated history entry — would now throw where it previously produced a harmless option. That is precisely the kind of break this feature must not cause. Guard it: `fromJson` passes `slideshow: null` and must therefore tolerate an empty URL, so relax the assert to run only when the option was built directly:

```dart
  const VideoQualityOption({
    ...
    this.slideshow,
    bool checked = true,
  }) : assert(
         !checked || downloadUrl != '' || slideshow != null,
         'An option with no download URL must carry a SlideshowSource.',
       );
```

and have `fromJson` pass `checked: false`. Add this test to the same file:

```dart
  test('a stored option with no url still deserializes', () {
    expect(
      () => VideoQualityOption.fromJson(const {
        'id': 'legacy',
        'label': 'originalMp4',
        'quality': '720p',
        'format': 'mp4',
        'downloadUrl': '',
      }),
      returnsNormally,
    );
  });
```

- [ ] **Step 5: Run to verify pass**

Run: `flutter test test/slideshow_source_test.dart test/slideshow_baseline_test.dart`
Expected: PASS, both files.

- [ ] **Step 6: Run the whole Dart suite — nothing else may move**

Run: `flutter test`
Expected: 222 passing + the new tests, 8 skipped, no failures. Any existing failure here means the assert or the new parameter broke a caller: fix the production code, never the test.

- [ ] **Step 7: Commit**

```bash
git add lib/models/ test/slideshow_source_test.dart
git commit -m "feat(models): carry a slideshow source on a quality option"
```

---

### Task 4: Keep the slideshow out of default selection

This is the task the constraint hangs on. A photo post today defaults to an image. Adding a video-kind option would make `bestMatch` prefer it and flip the default tab. It must not.

**Files:**
- Modify: `lib/core/utils/quality_helper.dart`
- Modify: `lib/models/video_metadata.dart:156-165` (`bestQuality`)
- Test: `test/quality_helper_test.dart` (add cases)
- Test: `test/media_helpers_test.dart` (add one case; do not edit the existing ones)

**Interfaces:**
- Consumes: `needsRendering` from Task 3
- Produces: `QualityHelper.rankOf` returns 0 for a slideshow; `bestMatch` excludes it from `videoOnly`; `VideoMetadata.bestQuality` skips it

**`bestQuality` has its own logic and must be patched too.** It does not call
`QualityHelper` at all — it returns the first option that is
`!isAudioOnly && !isImage`, and a slideshow is `MediaKind.video`, so it would
be returned ahead of the images. It feeds `selectedQuality` in
`video_extractor_provider.dart:80,210,297`, which is the app's default
selection: leaving it unpatched flips a photo post to the video tab, the exact
regression this feature must not cause.

- [ ] **Step 1: Write the failing tests**

Append to `test/quality_helper_test.dart`:

```dart
  test('a slideshow never becomes the default selection', () {
    const image = VideoQualityOption.image(
      id: 'i1',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn/1.jpg',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    final best = QualityHelper.bestMatch([image, slideshow], 'Highest');
    expect(best!.isImage, isTrue);
  });

  test('bestQuality skips a slideshow and still reports the image', () {
    // Guards the default selection: bestQuality feeds selectedQuality in
    // video_extractor_provider, so a slideshow winning here would move a photo
    // post's default onto the video tab.
    const image = VideoQualityOption.image(
      id: 'i1',
      label: ImageIndex(1),
      format: 'jpg',
      downloadUrl: 'https://cdn/1.jpg',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    final metadata = VideoMetadata(
      id: 'p',
      originalUrl: 'https://tiktok.com/@u/photo/1',
      title: 'photo post',
      author: 'someone',
      coverUrl: '',
      platform: VideoPlatform.tiktok,
      qualities: const [image, slideshow],
    );
    expect(metadata.bestQuality, same(image));
  });

  test('a slideshow does not outrank a real video', () {
    const video = VideoQualityOption.video(
      id: 'v',
      label: OriginalMp4(),
      quality: '720p',
      format: 'mp4',
      downloadUrl: 'https://cdn/v.mp4',
    );
    const slideshow = VideoQualityOption.slideshow(
      id: 's1',
      label: SlideshowVideo(1),
      source: SlideshowSource(imageUrls: ['https://cdn/1.jpg']),
    );
    expect(QualityHelper.rankOf(video) > QualityHelper.rankOf(slideshow), isTrue);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/quality_helper_test.dart`
Expected: FAIL — the slideshow currently ranks 1 and wins `bestMatch`.

- [ ] **Step 3: Add the branches**

In `rankOf`, immediately after the `isAudioOnly` line and before the image line:

```dart
    // A slideshow does not exist until it is rendered, so it must not win the
    // default selection away from the photos it is made of. It shares the
    // image tier: below every real video, above audio.
    if (option.needsRendering) return 0;
```

In `bestMatch`, extend the existing filter — add the term, do not rewrite the expression:

```dart
    final videoOnly = sorted
        .where((o) => !o.isAudioOnly && !o.isImage && !o.needsRendering)
        .toList();
```

In `lib/models/video_metadata.dart`, add the same term to `bestQuality`'s first
loop and leave the two loops below it alone:

```dart
  VideoQualityOption? get bestQuality {
    if (qualities.isEmpty) return null;
    for (final quality in qualities) {
      // A slideshow is not a file yet. Preferring it here would move a photo
      // post's default selection off its photos and onto the video tab.
      if (quality.needsRendering) continue;
      if (!quality.isAudioOnly && !quality.isImage) return quality;
    }
    ...
```

- [ ] **Step 4: Run to verify pass, and that the baseline held**

Run: `flutter test test/quality_helper_test.dart test/media_helpers_test.dart test/slideshow_baseline_test.dart test/extractor_fixture_test.dart`
Expected: PASS, all four, with no edits to any pre-existing test. `media_helpers_test.dart` is included because it owns the existing `bestQuality` cases — they must still pass untouched.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/quality_helper.dart test/quality_helper_test.dart
git commit -m "fix(quality): keep a slideshow out of the default selection"
```

---

### Task 5: Emit the option from the TikTok extractor

**Files:**
- Modify: `lib/services/extractors/tiktok_extractor.dart:85-96`
- Test: `test/extractor_fixture_test.dart` (add a test; leave the existing one alone)

**Interfaces:**
- Consumes: `VideoQualityOption.slideshow`, `SlideshowSource`, `SlideshowVideo`
- Produces: exactly one option with `needsRendering == true` for a photo post, id `tt_slideshow_<postId>`

- [ ] **Step 1: Write the failing test**

Append to `test/extractor_fixture_test.dart`:

```dart
  test('TikTok offers one rendered slideshow for a photo post', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok_images.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/photo/1',
    );

    final rendered =
        result.qualities.where((o) => o.needsRendering).toList();
    expect(rendered, hasLength(1));
    expect(rendered.single.format, 'mp4');
    expect(rendered.single.slideshow!.imageUrls, hasLength(2));
    // Relative CDN paths must already be absolute by the time they are handed
    // to the renderer, which has no idea what TikWM's host is.
    expect(rendered.single.slideshow!.imageUrls.last, startsWith('http'));
    expect(rendered.single.slideshow!.audioUrl, isNotNull);
    expect((rendered.single.label as SlideshowVideo).imageCount, 2);
  });

  test('TikTok offers no slideshow for a video post', () async {
    ExtractorHttp.postOverride = (_, _, _) async =>
        http.Response(fixture('tiktok.json'), 200);

    final result = await const TikTokExtractor().extract(
      'https://www.tiktok.com/@u/video/1',
    );

    expect(result.qualities.where((o) => o.needsRendering), isEmpty);
  });
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/extractor_fixture_test.dart`
Expected: FAIL — no option reports `needsRendering`.

- [ ] **Step 3: Emit it**

In `tiktok_extractor.dart`, after the image loop and before the `hdPlay` block, insert:

```dart
    // A photo post has no video upstream: TikWM's play/hdplay/wmplay fields
    // are empty for an album. The images are all there is, so offer to render
    // them into one, the way the post itself is presented on TikTok.
    if (images.isNotEmpty) {
      final imageUrls = [
        for (final image in images)
          if ((image?.toString() ?? '').isNotEmpty)
            _absolute(image.toString()),
      ];
      qualities.add(
        VideoQualityOption.slideshow(
          id: 'tt_slideshow_$id',
          mediaId: 'tt_slideshow_$id',
          label: SlideshowVideo(imageUrls.length),
          source: SlideshowSource(
            imageUrls: imageUrls,
            audioUrl: music != null && music.isNotEmpty
                ? _absolute(music)
                : null,
          ),
        ),
      );
    }
```

Move the `final music = data['music']?.toString();` line above this block so the audio URL is in scope; leave the audio option's own block where it is.

- [ ] **Step 4: Run to verify pass, plus the baseline**

Run: `flutter test test/extractor_fixture_test.dart test/slideshow_baseline_test.dart`
Expected: PASS. The baseline proves the default selection and the image list did not move.

- [ ] **Step 5: Commit**

```bash
git add lib/services/extractors/tiktok_extractor.dart test/extractor_fixture_test.dart
git commit -m "feat(tiktok): offer a rendered slideshow for photo posts"
```

---

### Task 6: The renderer interface and its unsupported stub

**Files:**
- Create: `lib/services/slideshow/slideshow_renderer.dart`
- Create: `lib/services/slideshow/slideshow_renderer_stub.dart`
- Create: `lib/services/slideshow/slideshow_failure.dart`
- Test: `test/slideshow_renderer_test.dart` (create)

**Interfaces:**
- Produces:
  - `enum SlideshowFailureKind { noImages, fetchFailed, encoderUnavailable, encodeFailed, outOfSpace }`
  - `class SlideshowException implements Exception { final SlideshowFailureKind kind; final String? detail; }`
  - `class SlideshowResult { final String filePath; final bool audioSkipped; }`
  - `abstract interface class SlideshowRenderer { bool get isSupported; Future<SlideshowResult> render({required List<String> imagePaths, String? audioPath, required Duration perImage, required int width, required int height, required String outputPath}); }`
  - `SlideshowRenderer createSlideshowRenderer()`

Follow the conditional-import shape already used by `lib/core/utils/platform_file.dart`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';
import 'package:nimble_clip/services/slideshow/slideshow_renderer_stub.dart';

void main() {
  test('the stub renderer reports itself unsupported', () {
    expect(const UnsupportedSlideshowRenderer().isSupported, isFalse);
  });

  test('the stub renderer refuses to render', () async {
    await expectLater(
      const UnsupportedSlideshowRenderer().render(
        imagePaths: const ['/tmp/1.jpg'],
        perImage: const Duration(seconds: 3),
        width: 1080,
        height: 1920,
        outputPath: '/tmp/out.mp4',
      ),
      throwsA(
        isA<SlideshowException>().having(
          (e) => e.kind,
          'kind',
          SlideshowFailureKind.encoderUnavailable,
        ),
      ),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/slideshow_renderer_test.dart`
Expected: FAIL — the files do not exist.

- [ ] **Step 3: Write the failure type, the interface, and the stub**

Write the three files to the signatures given in **Interfaces** above. The stub's `render` throws `SlideshowException(SlideshowFailureKind.encoderUnavailable)`. Nothing in these files may import Flutter widgets or localizations.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/slideshow_renderer_test.dart test/architecture_test.dart`
Expected: PASS. The architecture test is included deliberately — it is what catches a stray `views/` or localization import.

- [ ] **Step 5: Commit**

```bash
git add lib/services/slideshow/ test/slideshow_renderer_test.dart
git commit -m "feat(slideshow): add the renderer interface and its stub"
```

---

### Task 7: Fetch the assets to a temp directory

**Files:**
- Create: `lib/services/slideshow/slideshow_asset_fetcher.dart`
- Test: `test/slideshow_asset_fetcher_test.dart` (create)

**Interfaces:**
- Consumes: `SlideshowSource`, `SlideshowException`
- Produces: `class SlideshowAssets { final List<String> imagePaths; final String? audioPath; final Directory workingDir; }` and `Future<SlideshowAssets> fetchSlideshowAssets(SlideshowSource source, {required Directory into})`

- [ ] **Step 1: Write the failing tests**

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:nimble_clip/core/utils/http_helper.dart';
import 'package:nimble_clip/models/slideshow_source.dart';
import 'package:nimble_clip/services/slideshow/slideshow_asset_fetcher.dart';
import 'package:nimble_clip/services/slideshow/slideshow_failure.dart';

void main() {
  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('slideshow_test'));
  tearDown(() {
    ExtractorHttp.resetOverrides();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('images land on disk in source order', () async {
    ExtractorHttp.getOverride = (uri, _) async =>
        http.Response.bytes([1, 2, 3], 200);

    final assets = await fetchSlideshowAssets(
      const SlideshowSource(imageUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg']),
      into: temp,
    );

    expect(assets.imagePaths, hasLength(2));
    expect(File(assets.imagePaths.first).readAsBytesSync(), [1, 2, 3]);
    expect(assets.imagePaths.first, endsWith('image_0.jpg'));
    expect(assets.imagePaths.last, endsWith('image_1.jpg'));
    expect(assets.audioPath, isNull);
  });

  test('a failed audio fetch does not fail the whole render', () async {
    ExtractorHttp.getOverride = (uri, _) async => uri.path.endsWith('.mp3')
        ? http.Response('nope', 500)
        : http.Response.bytes([1], 200);

    final assets = await fetchSlideshowAssets(
      const SlideshowSource(
        imageUrls: ['https://cdn/a.jpg'],
        audioUrl: 'https://cdn/song.mp3',
      ),
      into: temp,
    );

    expect(assets.imagePaths, hasLength(1));
    expect(assets.audioPath, isNull);
  });

  test('a failed image fetch does fail the render', () async {
    ExtractorHttp.getOverride = (_, _) async => http.Response('nope', 404);

    await expectLater(
      fetchSlideshowAssets(
        const SlideshowSource(imageUrls: ['https://cdn/a.jpg']),
        into: temp,
      ),
      throwsA(isA<SlideshowException>().having(
        (e) => e.kind, 'kind', SlideshowFailureKind.fetchFailed)),
    );
  });

  test('an empty source is rejected before any request', () async {
    await expectLater(
      fetchSlideshowAssets(const SlideshowSource(imageUrls: []), into: temp),
      throwsA(isA<SlideshowException>().having(
        (e) => e.kind, 'kind', SlideshowFailureKind.noImages)),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/slideshow_asset_fetcher_test.dart`
Expected: FAIL — the fetcher does not exist.

- [ ] **Step 3: Implement it**

Fetch each image with `ExtractorHttp.getWithRetry`, writing `image_<index>.<ext>` where the extension comes from `MediaFormatHelper.inferImageFormat` on the URL. A non-200 for any image throws `fetchFailed`. Audio is fetched last, to `audio.mp3`; **any** audio failure is swallowed and leaves `audioPath` null, because a silent slideshow beats no slideshow. An empty `imageUrls` throws `noImages` before any request goes out.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/slideshow_asset_fetcher_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/services/slideshow/slideshow_asset_fetcher.dart test/slideshow_asset_fetcher_test.dart
git commit -m "feat(slideshow): fetch a post's images and music to a temp dir"
```

---

### Task 8: The Android encoder — picture only

Audio is deliberately deferred to Task 9. A silent MP4 that plays is the milestone here.

**Files:**
- Create: `android/app/src/main/kotlin/com/vannt/nimbleclip/SlideshowEncoder.kt`
- Modify: `android/app/src/main/kotlin/com/vannt/nimbleclip/MainActivity.kt` (register the channel beside the existing two, at the end of `configureFlutterEngine`)
- Test: `integration_test/slideshow_render_test.dart` (create)

**Interfaces:**
- Produces: MethodChannel `com.vannt.nimbleclip/slideshow`, method `render`, arguments `imagePaths: List<String>`, `audioPath: String?`, `perImageMs: Int`, `width: Int`, `height: Int`, `outputPath: String`; returns `mapOf("filePath" to String, "audioSkipped" to Boolean)`; errors with code `encode_failed` or `out_of_space`.

- [ ] **Step 1: Write the failing integration test**

```dart
// integration_test/slideshow_render_test.dart
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.vannt.nimbleclip/slideshow');

  test('three images become one playable mp4', () async {
    final dir = await getTemporaryDirectory();
    final paths = <String>[];
    for (var i = 0; i < 3; i++) {
      final file = File('${dir.path}/frame_$i.png');
      await file.writeAsBytes(_solidPng(i));
      paths.add(file.path);
    }
    final out = '${dir.path}/out.mp4';

    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': null,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });

    final file = File(result!['filePath'] as String);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(10000));
    expect(result['audioSkipped'], isTrue);
  });
}
```

Write `_solidPng(int)` in the same file as a helper producing a small distinct solid-colour PNG; do not pull in an image library for it.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test integration_test/slideshow_render_test.dart -d emulator-5554`
Expected: FAIL — `MissingPluginException`.

- [ ] **Step 3: Write the encoder**

`SlideshowEncoder.kt` exposes:

```kotlin
class SlideshowEncoder {
    data class Request(
        val imagePaths: List<String>,
        val audioPath: String?,
        val perImageMs: Int,
        val width: Int,
        val height: Int,
        val outputPath: String,
    )

    data class Result(val filePath: String, val audioSkipped: Boolean)

    fun encode(request: Request): Result { ... }
}
```

The video path:

1. Configure `MediaCodec.createEncoderByType("video/avc")` with `MediaFormat.createVideoFormat("video/avc", width, height)`, `COLOR_FormatSurface`, 30fps, a 1-second I-frame interval, and a bitrate of `width * height * 4`.
2. Take the encoder's input `Surface`, wrap it in a `android.media.MediaCodec`-driven loop that, per image, decodes the file with `BitmapFactory`, draws it onto the surface `Canvas` and submits `perImageMs / 33` frames.
3. Per frame, draw in this order: the image scaled to **cover** the canvas and blurred, then the image scaled to **fit**, centred. Blur with `RenderEffect` on API 31+, and on older devices with a downscale-to-1/16-then-upscale, which costs nothing and reads as a blur at this size.
4. Drain the encoder into `MediaMuxer` (`MUXER_OUTPUT_MPEG_4`), setting presentation timestamps from a monotonic frame counter at 30fps.
5. Signal end of stream, stop and release everything in a `finally`, and return `Result(outputPath, audioSkipped = true)` — Task 9 makes that flag meaningful.

Throw a Kotlin exception on failure; the channel handler maps it to `result.error("encode_failed", message, null)`, and an `IOException` whose message mentions space to `out_of_space`.

- [ ] **Step 4: Register the channel**

At the end of `configureFlutterEngine` in `MainActivity.kt`, matching the style of the two existing registrations:

```kotlin
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.vannt.nimbleclip/slideshow",
        ).setMethodCallHandler { call, result ->
            if (call.method != "render") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            Thread {
                try {
                    val encoded = SlideshowEncoder().encode(
                        SlideshowEncoder.Request(
                            imagePaths = call.argument<List<String>>("imagePaths").orEmpty(),
                            audioPath = call.argument<String>("audioPath"),
                            perImageMs = call.argument<Int>("perImageMs") ?: 3000,
                            width = call.argument<Int>("width") ?: 1080,
                            height = call.argument<Int>("height") ?: 1920,
                            outputPath = call.argument<String>("outputPath")!!,
                        ),
                    )
                    runOnUiThread {
                        result.success(
                            mapOf(
                                "filePath" to encoded.filePath,
                                "audioSkipped" to encoded.audioSkipped,
                            ),
                        )
                    }
                } catch (error: Exception) {
                    runOnUiThread { result.error("encode_failed", error.message, null) }
                }
            }.start()
        }
```

Encoding on a worker thread is not optional: a multi-second encode on the platform thread freezes the UI and trips Android's ANR watchdog.

- [ ] **Step 5: Run to verify pass**

Run: `flutter test integration_test/slideshow_render_test.dart -d emulator-5554`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add android/ integration_test/slideshow_render_test.dart
git commit -m "feat(android): encode a photo post's images into a silent mp4"
```

---

### Task 9: Add the music track

The riskiest step, isolated so a failure here cannot take the rest down. `MediaMuxer` will not accept MP3 in an MP4, and TikWM serves MP3, so the track must be transcoded to AAC.

**Files:**
- Modify: `android/app/src/main/kotlin/com/vannt/nimbleclip/SlideshowEncoder.kt`
- Test: `integration_test/slideshow_render_test.dart` (add cases)

- [ ] **Step 1: Write the failing tests**

Add to the integration file:

```dart
  test('a slideshow with music carries an audio track', () async {
    final dir = await getTemporaryDirectory();
    final audio = File('${dir.path}/song.mp3');
    await audio.writeAsBytes(await _fixtureBytes('slideshow.mp3'));
    // ... build three images as above, then:
    final result = await channel.invokeMapMethod<String, dynamic>('render', {
      'imagePaths': paths,
      'audioPath': audio.path,
      'perImageMs': 1000,
      'width': 1080,
      'height': 1920,
      'outputPath': out,
    });
    expect(result!['audioSkipped'], isFalse);
    expect(await _hasAudioTrack(result['filePath'] as String), isTrue);
  });

  test('a corrupt track yields a silent video, not a failure', () async {
    // ... same, but write garbage bytes as the mp3
    expect(result!['audioSkipped'], isTrue);
    expect(File(result['filePath'] as String).existsSync(), isTrue);
  });
```

`_hasAudioTrack` reads the file back with a `MediaMetadataRetriever` through a small test-only channel method, or — simpler and preferred — asserts on `METADATA_KEY_HAS_AUDIO` exposed by adding a `probe` method to the same channel. Serve `slideshow.mp3` from `tool/fixture_server.js` alongside the existing fixtures.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test integration_test/slideshow_render_test.dart -d emulator-5554`
Expected: FAIL — `audioSkipped` is hardcoded true.

- [ ] **Step 3: Implement the transcode**

Inside `encode`, after the video track is written and before the muxer stops:

1. `MediaExtractor.setDataSource(audioPath)`, select the first `audio/` track.
2. Decode it with `MediaCodec.createDecoderByType(mime)` into PCM.
3. Encode that PCM with `MediaCodec.createEncoderByType("audio/mp4a-latm")` at 44.1kHz stereo, 128kbps.
4. Add the AAC track to the muxer and write the encoded buffers, stopping at `min(audioDuration, videoDuration)`.

Wrap the whole audio stage in `try/catch (Exception)`. On any failure: log, leave the video track alone, and return `audioSkipped = true`. **The video must already be fully written before the audio stage begins**, so a failure there can never corrupt the picture.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test integration_test/slideshow_render_test.dart -d emulator-5554`
Expected: PASS, 3 tests.

- [ ] **Step 5: Commit**

```bash
git add android/ integration_test/ tool/fixture_server.js test/fixtures/
git commit -m "feat(android): mux a post's music into the rendered slideshow"
```

---

### Task 10: Wire the renderer into the download flow

**Files:**
- Create: `lib/services/slideshow/slideshow_renderer_android.dart`
- Modify: `lib/services/slideshow/slideshow_renderer.dart` (conditional export)
- Modify: `lib/providers/download_provider.dart:255` (early branch only)
- Test: `test/slideshow_download_guard_test.dart` (create)

**Interfaces:**
- Consumes: everything from Tasks 3, 6, 7
- Produces: `MethodChannelSlideshowRenderer`; `DownloadProvider.startNewDownloads` never builds a `DownloadTask` from an option where `needsRendering`

- [ ] **Step 1: Write the failing guard test**

```dart
test('a slideshow option never enters the url download path', () async {
  final provider = DownloadProvider(downloadService: InertDownloadService());
  final tasks = await provider.startNewDownloads(
    metadata: _photoPostMetadata(),   // built with one slideshow option only
    qualities: [_slideshowOption()],
    l10n: enL10n,
  );
  expect(tasks, isEmpty);
  expect(provider.tasks.any((t) => t.downloadUrl.isEmpty), isFalse);
});
```

Reuse `test/support/inert_download_service.dart`; do not write a second fake.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/slideshow_download_guard_test.dart`
Expected: FAIL — a `DownloadTask` is created with an empty `downloadUrl`.

- [ ] **Step 3: Add the early branch**

At the top of `startNewDownloads`, after the `await _historyReady;` line and before `if (qualities.isEmpty)`:

```dart
    // A slideshow has no URL to fetch: it is rendered first, and the finished
    // file enters history as a file that already exists. Splitting it off here
    // keeps the URL path below untouched.
    final renderable = qualities.where((q) => q.needsRendering).toList();
    if (renderable.isNotEmpty) {
      unawaited(_renderSlideshows(renderable, metadata, l10n));
      qualities = qualities.where((q) => !q.needsRendering).toList();
    }
```

Everything below stays exactly as it is. `_renderSlideshows` fetches assets into `getTemporaryDirectory()`, calls the renderer, moves the result into the download directory via the existing storage service, records it in history, deletes the temp dir in a `finally`, and surfaces `audioSkipped` as a warning.

- [ ] **Step 4: Write the Android renderer**

`MethodChannelSlideshowRenderer` invokes `render` on `com.vannt.nimbleclip/slideshow`, maps `PlatformException` codes to `SlideshowFailureKind`, and reports `isSupported => true`. `slideshow_renderer.dart` conditionally exports it for `dart.library.io` on Android and the stub elsewhere, mirroring `platform_file.dart`.

- [ ] **Step 5: Run to verify pass, and the whole Dart suite**

Run: `flutter test`
Expected: PASS throughout, existing tests unedited.

- [ ] **Step 6: Commit**

```bash
git add lib/services/slideshow/ lib/providers/download_provider.dart test/slideshow_download_guard_test.dart
git commit -m "feat(downloads): render a slideshow instead of fetching it"
```

---

### Task 11: Show the option only where it can run

**Files:**
- Modify: `lib/views/home/widgets/video_result_card.dart`
- Test: `test/slideshow_result_card_test.dart` (create)

**Interfaces:**
- Consumes: `createSlideshowRenderer().isSupported`, `needsRendering`

- [ ] **Step 1: Write the failing tests**

```dart
testWidgets('the slideshow option shows when the renderer supports it',
    (tester) async { ... expect(find.textContaining('Slideshow'), findsOneWidget); });

testWidgets('the slideshow option is hidden when it cannot run',
    (tester) async { ... expect(find.textContaining('Slideshow'), findsNothing); });

testWidgets('the slideshow row fits a phone-width screen', (tester) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  // ... pump, then:
  expect(tester.takeException(), isNull);
});
```

The narrow-width case is not optional: the 800px default test surface hides every phone-width overflow, which is how such bugs have reached users before.

- [ ] **Step 2: Run to verify failure**

Run: `flutter test test/slideshow_result_card_test.dart`
Expected: FAIL.

- [ ] **Step 3: Filter the options**

In `video_result_card.dart`, where the option list for the video tab is built, drop options where `needsRendering && !renderer.isSupported`. Inject the renderer so the widget test can supply a fake — a constructor parameter defaulting to `createSlideshowRenderer()`, not a global lookup.

- [ ] **Step 4: Run to verify pass**

Run: `flutter test test/slideshow_result_card_test.dart test/screens_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/views/ test/slideshow_result_card_test.dart
git commit -m "feat(home): offer the slideshow only where it can be rendered"
```

---

### Task 12: Document and verify the whole thing

**Files:**
- Modify: `CHANGELOG.md`, `README.md`

- [ ] **Step 1: Add the changelog entry**

Under the unreleased heading, following the existing wording style. A release with a version bump but no changelog notes fails CI, so this is not optional housekeeping.

- [ ] **Step 2: Note the feature in the README**

One line in the feature list, and a note that it is Android-only for now.

- [ ] **Step 3: Run the full check**

Run: `powershell -ExecutionPolicy Bypass -File .\tool\check_all.ps1`
Expected: all 7 steps pass, including the Android suite.

- [ ] **Step 4: Confirm the baseline is untouched**

Run: `git diff main --stat -- test/` and read it. Every listed test file must be an addition or an append. **A modified line inside a pre-existing test is a regression signal** — investigate it rather than accepting it.

- [ ] **Step 5: Commit**

```bash
git add CHANGELOG.md README.md
git commit -m "docs: note device-rendered TikTok slideshows"
```

---

## Notes for the executor

- `flutter clean` before any local release APK build if the Android suite ran first; otherwise `flutter build apk --release` fails with `package dev.flutter.plugins.integration_test does not exist`.
- `pubspec.lock` may be dirty with an unrelated dependency upgrade. Do not fold it into any commit here.
- Tasks 8 and 9 need a running emulator. `tool/run_android_emulator.ps1` starts the default `Aegis_API_34`.
