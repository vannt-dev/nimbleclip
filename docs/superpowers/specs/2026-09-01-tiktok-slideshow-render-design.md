# TikTok photo posts — render the images into one video

Date: 2026-09-01
Status: proposed
Platform scope: Android only in this pass

## The problem

A TikTok photo post gives the user a set of images and a music track, and
nothing that plays as a video. SnapTik offers "download slideshow as video" for
these posts. This spec adds the same thing to NimbleClip.

## What the source gives us, and what it does not

TikWM returns, for a photo post, `images[]` and `music`. It returns no rendered
video. The `play` / `hdplay` / `wmplay` fields are video-post fields and carry
nothing for an album — which is exactly why `TikTokExtractor` guards all three
with `images.isEmpty` (`tiktok_extractor.dart:101,116,131`). Those guards are
correct and stay.

This was checked against the field definitions of an independent TikWM client
(`heilkit/tt`), whose `Post.ContentUrls()` returns only `Images` when
`IsAlbum()` is true. There is no mp4 upstream to un-suppress. SnapTik renders
one server-side; we have no server, so we render on the device.

## The overriding constraint

The existing video and image flows are finished work. Nothing in this feature
may change how they behave. Every decision below is subordinate to that, and
§"Keeping the existing flows intact" states how it is enforced rather than
merely intended.

## Design

### Boundaries

Four new units, each with one job:

| Unit | Job | Depends on |
|---|---|---|
| `SlideshowSource` (models) | Plain data: `imageUrls`, `audioUrl?`, `perImage`, canvas size | nothing |
| `SlideshowAssetFetcher` (services) | Fetch images + audio to a temp dir, validate them | `ExtractorHttp`, `MediaFileValidator` |
| `SlideshowRenderer` (services) | `bool get isSupported`; `render(files) → File` | `dart:io` only |
| `SlideshowEncoder.kt` (android) | Bitmaps → canvas → H.264 → MP4 | no network |

`SlideshowRenderer` picks its implementation by conditional import, the pattern
already used by `platform_file.dart` / `_stub.dart` / `_web.dart`. Android talks
over MethodChannel `com.vannt.nimbleclip/slideshow`, registered beside the two
existing channels in `MainActivity.kt:50,73`. iOS and Web get a stub whose
`isSupported` is false.

The native side never touches the network. Browser-navigation headers, retry,
and the `ExtractionPolicy.allowExternalServices` switch stay in Dart, where they
already live and are already tested. This is the whole reason fetching is not
pushed into Kotlin.

`test/architecture_test.dart` is satisfied: no new file under `services/`,
`models/` or `core/` imports `views/`, `providers/`, or the generated
localizations. The encoder reports failures as an enum; wording is applied by
the view layer.

### Data flow

```
TikTokExtractor  → VideoQualityOption with a SlideshowSource
                   (always emitted; never platform-dependent)
      ↓            UI filters on SlideshowRenderer.isSupported
user selects     → SlideshowAssetFetcher writes N images + 1 mp3 to a temp dir
      ↓            (local file paths cross the channel, never URLs)
SlideshowEncoder → decode → 1080×1920 canvas, blurred fill → H.264 30fps
                 → MediaMuxer
      ↓
finished mp4     → the existing save-to-gallery and history path, entered as a
                   file that already exists on disk
```

### The model change

`VideoQualityOption` gains one nullable field:

```dart
final SlideshowSource? slideshow;
bool get needsRendering => slideshow != null;
```

The option's `kind` stays `MediaKind.video` — it does produce a video — and its
`downloadUrl` is the empty string, because there is nothing to fetch.

**`MediaKind` is deliberately not widened.** It has two consumers that have
nothing to do with quality options: `MediaFileValidator` uses it to classify
bytes on disk (`media_file_validator.dart:19-74`), and `DownloadTask.fromJson`
walks `MediaKind.values` (`download_task.dart:197`). A `MediaKind.slideshow`
would be meaningless to both — there are no "slideshow bytes" — and would put a
new case into code paths this feature has no business touching. Leaving the enum
alone also means the Video tab appears for a photo post with no change to the
tab logic at all.

**On the empty `downloadUrl`.** Making `downloadUrl` nullable would let the
analyzer enumerate every site that must now handle the absent case, which is the
more rigorous option in the abstract. It is rejected here: `downloadUrl` appears
at 117 sites across 29 files, including `DownloadTask` and most of the existing
test suite. A refactor of that blast radius is a larger threat to the finished
flows than the sentinel is. The sentinel is fenced instead:

- `assert(downloadUrl.isNotEmpty || slideshow != null)` in the base constructor;
- a test asserting `DownloadProvider` never builds a `DownloadTask` from an
  option where `needsRendering` is true.

A new `SlideshowVideo` descriptor joins `QualityDescriptor`, carrying the image
count, with en and vi strings and a token so history round-trips.
`QualityHelper.sortedByQuality` gets an explicit branch for it rather than
letting it fall into string comparison — that comparator is where an image's
`quality` of `'Original'` already parses as 2160, and the new option must not
join that.

### Render parameters

1080×1920, 30fps, 3s per image. Images vary in aspect ratio and H.264 needs one
fixed frame for the clip, so each image is fitted inside the canvas and the
remaining area is filled with the same image, scaled up and blurred — how TikTok
itself presents them. No content is cropped and no wide black bars appear.

Clip length is the shorter of the image run and the music track.

### Audio is the risky part

`MediaMuxer` will not put MP3 into an MP4, and TikWM serves the music as MP3. So
the encoder must run `MediaExtractor` → decode to PCM → encode AAC → mux. This
is the largest and most failure-prone piece of the native work, and it is
sequenced last.

**If the audio step fails, the render still succeeds and produces a silent
video**, with a warning surfaced to the user. A slideshow without music is
usable; a failed render is not.

### Failures

Rendering is not extraction, so `ExtractionFailureKind` is not widened — that
taxonomy stays clean. A separate small enum covers it: `noImages`,
`fetchFailed`, `encoderUnavailable`, `encodeFailed`, `outOfSpace`, plus
`audioSkipped`, which is a warning rather than a failure. Wording is applied in
the view layer, mirroring `extraction_failure_text.dart`.

## Keeping the existing flows intact

Four enforced rules, not intentions:

1. **No existing test is edited.** The suite as it stands (222 passing, 8
   skipped live smoke tests) is the regression baseline. If a change requires
   editing an existing expectation, that is a regression signal: stop and
   redesign rather than update the test.
2. **Shared code is extended, never rewritten.** `DownloadProvider` gets an
   early `if (option.needsRendering)` branch at the entry point; the existing
   body below it is unchanged. `QualityHelper` gets an added branch, not a
   reworked comparator.
3. **Characterisation before change.** Before `QualityHelper` is touched, a test
   locks the current ordering of the existing fixtures. It must still pass
   afterwards.
4. **Provably removable.** The feature is reachable only through the new option,
   which is emitted only for TikTok photo posts and shown only where
   `isSupported`. With the renderer reporting unsupported, the app behaves
   exactly as it does today — which is also what iOS and Web will run.

## Test strategy

The repository has a real Android emulator suite, so the strongest evidence
lives there.

- **Integration (emulator).** Encode three fixture images plus a fixture MP3;
  assert the output is a valid MP4 with a 1080×1920 video track, an audio track,
  and a duration of about 3 × `perImage`. Served through `tool/fixture_server.js`
  like the existing cases.
- **Integration (emulator), audio failure.** Feed a corrupt MP3 and assert a
  silent but valid MP4 comes back, not an error.
- **Unit.** The extractor emits exactly one slideshow option for a photo post
  (extending `tiktok_images.json`) and none for a video post; ranking is
  unchanged; the descriptor round-trips through JSON.
- **Widget.** The Video tab appears when the renderer is supported and is absent
  when it is not — checked at phone width as well, since the 800px default test
  surface hides narrow-screen overflow.
- **Guard.** No slideshow option ever reaches the URL download path.

## Out of scope

iOS (`AVAssetWriter`), Web, transitions and motion effects, and choosing a
subset or order of images before rendering.
