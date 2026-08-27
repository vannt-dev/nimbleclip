# Extractor Decoupling Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the pre-translated failure strings thrown by the extractor layer with typed failure values, move `VideoPlatform`'s Flutter presentation getters into the view layer, and add a test that pins the layer boundaries.

**Architecture:** Extractors throw `ExtractionException(ExtractionFailure(kind, detail:))` instead of a localized `String`. A pure function in `lib/l10n/` maps a failure to text; `VideoExtractorProvider` calls it in its `catch` blocks, so `errorMessage` stays a `String` and no widget changes. `brandColor` and `icon` move from the `VideoPlatform` enum to an extension under `lib/core/theme/`, keeping every call site's text identical.

**Tech Stack:** Flutter 3.47, Dart SDK ^3.12.2, `flutter_test`, generated `AppLocalizations` (en + vi).

**Spec:** `docs/superpowers/specs/2026-08-27-extractor-decoupling-design.md`

## Global Constraints

- Dart formatting, `flutter analyze`, and the full test suite must pass before every commit. The repo's pre-commit hook runs the first three; `flutter analyze` can take over two minutes on the first run after a branch switch, so allow a long timeout.
- Commit subjects follow Conventional Commits; `.githooks/commit-msg` rejects anything else.
- **Never add a `Co-Authored-By` trailer to a commit message in this repo.**
- Nothing persisted may change. `DownloadTask.qualityLabel`, `sourceOptionId`, the history JSON and the receipt JSON stay exactly as they are.
- `extract(String url, AppLocalizations l10n)` keeps its `l10n` parameter. Quality labels still need it; removing it is phase 2.
- **Quality labels are out of scope.** If a change starts to require touching `VideoQualityOption.label`, stop and leave it for phase 2.
- Line width 80 where practical, matching the existing source.

---

### Task 1: Failure types and their text

**Files:**
- Create: `lib/services/extractors/extraction_failure.dart`
- Create: `lib/l10n/extraction_failure_text.dart`
- Test: `test/extraction_failure_text_test.dart`

**Interfaces:**
- Consumes: `AppLocalizations` from `lib/l10n/generated/app_localizations.dart`.
- Produces: `ExtractionFailureKind` (enum, 21 values listed below), `ExtractionFailure` (`const ExtractionFailure(this.kind, {this.detail})`, fields `kind` and `String? detail`), and `String describeExtractionFailure(ExtractionFailure failure, AppLocalizations l10n)`. Task 2 depends on all three.

This task adds no production wiring — nothing throws these types yet. That happens in Task 2. Keeping them separate means the text mapping is fully tested before the breaking type change lands.

- [ ] **Step 1: Write the failing test**

Create `test/extraction_failure_text_test.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/l10n/extraction_failure_text.dart';
import 'package:nimble_clip/l10n/generated/app_localizations.dart';
import 'package:nimble_clip/services/extractors/extraction_failure.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final vi = lookupAppLocalizations(const Locale('vi'));

  test('every failure kind renders non-empty text in both locales', () {
    for (final kind in ExtractionFailureKind.values) {
      final failure = ExtractionFailure(kind, detail: 'boom');
      for (final l10n in [en, vi]) {
        final text = describeExtractionFailure(failure, l10n);
        expect(text, isNotEmpty, reason: '$kind produced empty text');
        // A missed switch arm would leak the enum name to the user.
        expect(text, isNot(contains('ExtractionFailureKind')), reason: '$kind');
      }
    }
  });

  test('kinds without a detail ignore one that is supplied', () {
    const withDetail = ExtractionFailure(
      ExtractionFailureKind.xNoVideo,
      detail: 'ignored',
    );
    const without = ExtractionFailure(ExtractionFailureKind.xNoVideo);
    expect(
      describeExtractionFailure(withDetail, en),
      describeExtractionFailure(without, en),
    );
  });

  test('detail is substituted into the kinds that take one', () {
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: 'socket closed',
        ),
        en,
      ),
      contains('socket closed'),
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.tiktokServiceStatus,
          detail: '503',
        ),
        en,
      ),
      contains('503'),
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.youtubePlaybackRejected,
          detail: 'AGE_VERIFICATION_REQUIRED',
        ),
        en,
      ),
      contains('AGE_VERIFICATION_REQUIRED'),
    );
  });

  test('a TikTok server message is passed through, prefixed', () {
    // Preserves today's behaviour: when TikTok supplies its own `msg`, that
    // text is shown verbatim rather than the generic localized sentence.
    expect(
      describeExtractionFailure(
        const ExtractionFailure(
          ExtractionFailureKind.tiktokInvalidData,
          detail: 'video removed',
        ),
        en,
      ),
      'TikTok: video removed',
    );
    expect(
      describeExtractionFailure(
        const ExtractionFailure(ExtractionFailureKind.tiktokInvalidData),
        en,
      ),
      en.tiktokInvalidData,
    );
  });

  test('translations actually differ between locales', () {
    const failure = ExtractionFailure(ExtractionFailureKind.invalidLink);
    expect(
      describeExtractionFailure(failure, en),
      isNot(describeExtractionFailure(failure, vi)),
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/extraction_failure_text_test.dart`
Expected: FAIL to compile — `Error when reading 'lib/services/extractors/extraction_failure.dart': The system cannot find the file specified` and `Undefined name 'describeExtractionFailure'`.

- [ ] **Step 3: Create the failure types**

Create `lib/services/extractors/extraction_failure.dart`:

```dart
/// Why an extraction stopped.
///
/// Extractors report a kind rather than a sentence so that the layer stays
/// free of presentation text: the same failure renders differently per locale,
/// and tests can assert on identity instead of English prose.
enum ExtractionFailureKind {
  invalidLink,
  noDownloadStreams,
  externalServicesDisabled,

  /// Detail: the underlying error.
  linkAccessFailed,

  facebookNoVideo,
  genericNoVideo,
  instagramInvalidPost,
  instagramLoginRequired,

  /// Detail: the underlying error.
  tiktokConnectionFailed,

  /// Detail: the message TikTok supplied, when it supplied one.
  tiktokInvalidData,

  tiktokNoStreams,

  /// Detail: the HTTP status TikTok returned.
  tiktokServiceStatus,

  xInvalidPost,
  xNoVideo,
  youtubeCipherUnsupported,
  youtubeInvalidId,
  youtubeNoPlayerData,
  youtubeNoStreams,

  /// Detail: the underlying error.
  youtubeInvalidData,

  /// Detail: the underlying error.
  youtubeLoadFailed,

  /// Detail: the reason YouTube gave.
  youtubePlaybackRejected,
}

/// A failure kind plus the one piece of context some kinds carry.
///
/// A single nullable `detail` rather than a payload type per kind: six kinds
/// use it, each with exactly one substitution, and each is already a string at
/// the throw site. Kinds that take no detail ignore one if it is supplied.
class ExtractionFailure {
  const ExtractionFailure(this.kind, {this.detail});

  final ExtractionFailureKind kind;
  final String? detail;

  @override
  String toString() =>
      detail == null ? 'ExtractionFailure(${kind.name})'
                     : 'ExtractionFailure(${kind.name}, $detail)';
}
```

- [ ] **Step 4: Create the text mapping**

Create `lib/l10n/extraction_failure_text.dart`:

```dart
import '../services/extractors/extraction_failure.dart';
import 'generated/app_localizations.dart';

/// Renders [failure] in the caller's language.
///
/// The switch is exhaustive on purpose: adding a kind without adding its text
/// is a compile error rather than a blank message in the UI.
String describeExtractionFailure(
  ExtractionFailure failure,
  AppLocalizations l10n,
) {
  final detail = failure.detail;
  return switch (failure.kind) {
    ExtractionFailureKind.invalidLink => l10n.invalidLink,
    ExtractionFailureKind.noDownloadStreams => l10n.noDownloadStreams,
    ExtractionFailureKind.externalServicesDisabled =>
      l10n.externalServicesDisabled,
    ExtractionFailureKind.linkAccessFailed =>
      l10n.linkAccessFailed(detail ?? ''),
    ExtractionFailureKind.facebookNoVideo => l10n.facebookNoVideo,
    ExtractionFailureKind.genericNoVideo => l10n.genericNoVideo,
    ExtractionFailureKind.instagramInvalidPost => l10n.instagramInvalidPost,
    ExtractionFailureKind.instagramLoginRequired => l10n.instagramLoginRequired,
    ExtractionFailureKind.tiktokConnectionFailed =>
      l10n.tiktokConnectionFailed(detail ?? ''),
    // TikTok sometimes explains the failure itself. That text is not
    // translatable, so it is shown verbatim when present.
    ExtractionFailureKind.tiktokInvalidData =>
      detail != null && detail.isNotEmpty
          ? 'TikTok: $detail'
          : l10n.tiktokInvalidData,
    ExtractionFailureKind.tiktokNoStreams => l10n.tiktokNoStreams,
    ExtractionFailureKind.tiktokServiceStatus =>
      l10n.tiktokServiceStatus(int.tryParse(detail ?? '') ?? 0),
    ExtractionFailureKind.xInvalidPost => l10n.xInvalidPost,
    ExtractionFailureKind.xNoVideo => l10n.xNoVideo,
    ExtractionFailureKind.youtubeCipherUnsupported =>
      l10n.youtubeCipherUnsupported,
    ExtractionFailureKind.youtubeInvalidId => l10n.youtubeInvalidId,
    ExtractionFailureKind.youtubeNoPlayerData => l10n.youtubeNoPlayerData,
    ExtractionFailureKind.youtubeNoStreams => l10n.youtubeNoStreams,
    ExtractionFailureKind.youtubeInvalidData =>
      l10n.youtubeInvalidData(detail ?? ''),
    ExtractionFailureKind.youtubeLoadFailed =>
      l10n.youtubeLoadFailed(detail ?? ''),
    ExtractionFailureKind.youtubePlaybackRejected =>
      l10n.youtubePlaybackRejected(detail ?? ''),
  };
}
```

Note: `l10n.tiktokServiceStatus` is generated as `String tiktokServiceStatus(int status)` — verified at `lib/l10n/generated/app_localizations.dart:993` — which is why the detail is parsed back to an `int` here. `linkAccessFailed`, `tiktokConnectionFailed`, `youtubeInvalidData`, `youtubeLoadFailed` and `youtubePlaybackRejected` all take a `String`.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/extraction_failure_text_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/services/extractors/extraction_failure.dart lib/l10n/extraction_failure_text.dart test/extraction_failure_text_test.dart
git commit -F - <<'MSG'
feat(extractors): add typed extraction failures and their text

Introduces `ExtractionFailureKind` and `ExtractionFailure` so the
extractor layer can report why an extraction stopped without carrying a
sentence that has already been translated, plus the exhaustive mapping
that renders one in the caller's language.

Nothing throws these yet; the switch-over is the next change.
MSG
```

---

### Task 2: Throw and render typed failures

**Files:**
- Modify: `lib/services/extractors/base_extractor.dart` (`ExtractionException`)
- Modify: `lib/services/extractors/registry.dart:37,42`
- Modify: `lib/services/extractors/facebook_extractor.dart:123,132`
- Modify: `lib/services/extractors/generic_extractor.dart:84,198`
- Modify: `lib/services/extractors/instagram_extractor.dart:167,183`
- Modify: `lib/services/extractors/tiktok_extractor.dart:32,44,52,57,151`
- Modify: `lib/services/extractors/twitter_extractor.dart:43,47,56`
- Modify: `lib/services/extractors/youtube_extractor.dart:46,127,137,144,151,239`
- Modify: `lib/providers/video_extractor_provider.dart:250-256` (`_readableError`)
- Test: `test/widget_test.dart`, `test/extractor_fixture_test.dart`

**Interfaces:**
- Consumes: `ExtractionFailure`, `ExtractionFailureKind`, `describeExtractionFailure` from Task 1.
- Produces: `ExtractionException.failure` of type `ExtractionFailure`, replacing `ExtractionException.message`. `diagnosticCode` and `attemptedStrategies` are unchanged.

This task is deliberately one unit. Changing `ExtractionException`'s constructor breaks every throw site at compile time, so they cannot land separately.

- [ ] **Step 1: Write the failing test**

Add to `test/widget_test.dart`, inside the existing `main()`:

```dart
  test('an extraction failure reaches the UI as localized text', () async {
    final registry = _FailingExtractorRegistry(
      const ExtractionException(
        ExtractionFailure(ExtractionFailureKind.xNoVideo),
      ),
    );
    final provider = VideoExtractorProvider(extractorRegistry: registry);

    await provider.analyzeUrl('https://x.com/a/status/1', l10n: l10n);

    // The trap this guards: `_readableError` used to call `toString()`, which
    // after this change would surface `ExtractionFailureKind.xNoVideo`.
    expect(provider.errorMessage, l10n.xNoVideo);
    expect(provider.errorMessage, isNot(contains('ExtractionFailureKind')));
  });

  test('a non-extraction error still falls back to its message', () async {
    final registry = _FailingExtractorRegistry(Exception('network down'));
    final provider = VideoExtractorProvider(extractorRegistry: registry);

    await provider.analyzeUrl('https://x.com/a/status/1', l10n: l10n);

    expect(provider.errorMessage, 'network down');
  });
```

Add this fake near the other test doubles in `test/widget_test.dart`:

```dart
class _FailingExtractorRegistry implements ExtractorRegistry {
  _FailingExtractorRegistry(this.error);

  final Object error;

  @override
  Future<VideoMetadata> extract(String rawUrl, AppLocalizations l10n) async {
    throw error;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

Add the imports `package:nimble_clip/services/extractors/extraction_failure.dart` and `package:nimble_clip/services/extractors/base_extractor.dart` to the test file.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/widget_test.dart --plain-name "extraction failure reaches the UI"`
Expected: FAIL to compile — `ExtractionException` does not yet accept an `ExtractionFailure`.

- [ ] **Step 3: Change `ExtractionException`**

In `lib/services/extractors/base_extractor.dart`, replace the class and add the import `import 'extraction_failure.dart';`:

```dart
/// Thrown when a link is recognised but no downloadable stream could be found.
///
/// Carries the failure's identity rather than a sentence, so the layer stays
/// free of presentation text. Callers render it with
/// `describeExtractionFailure`.
class ExtractionException implements Exception {
  const ExtractionException(
    this.failure, {
    this.diagnosticCode,
    this.attemptedStrategies = const [],
  });

  final ExtractionFailure failure;
  final String? diagnosticCode;
  final List<String> attemptedStrategies;

  @override
  String toString() => 'ExtractionException(${failure.kind.name})';
}
```

- [ ] **Step 4: Migrate every throw site**

Each site keeps its `diagnosticCode` and `attemptedStrategies` arguments untouched; only the first argument changes. Add `import 'extraction_failure.dart';` to each file (in `registry.dart` it is `import 'extraction_failure.dart';` alongside the existing extractor imports).

| File:line | Was | Becomes |
|---|---|---|
| `registry.dart:37` | `l10n.invalidLink` | `const ExtractionFailure(ExtractionFailureKind.invalidLink)` |
| `registry.dart:42` | `l10n.noDownloadStreams` | `const ExtractionFailure(ExtractionFailureKind.noDownloadStreams)` |
| `facebook_extractor.dart:123` | `l10n.facebookNoVideo` | `const ExtractionFailure(ExtractionFailureKind.facebookNoVideo)` |
| `facebook_extractor.dart:132` | `l10n.facebookNoVideo` | `const ExtractionFailure(ExtractionFailureKind.facebookNoVideo)` |
| `generic_extractor.dart:84` | `l10n.linkAccessFailed(e.toString())` | `ExtractionFailure(ExtractionFailureKind.linkAccessFailed, detail: e.toString())` |
| `generic_extractor.dart:198` | `l10n.genericNoVideo` | `const ExtractionFailure(ExtractionFailureKind.genericNoVideo)` |
| `instagram_extractor.dart:167` | `l10n.instagramInvalidPost` | `const ExtractionFailure(ExtractionFailureKind.instagramInvalidPost)` |
| `instagram_extractor.dart:183` | `l10n.instagramLoginRequired` | `const ExtractionFailure(ExtractionFailureKind.instagramLoginRequired)` |
| `tiktok_extractor.dart:32` | `l10n.externalServicesDisabled` | `const ExtractionFailure(ExtractionFailureKind.externalServicesDisabled)` |
| `tiktok_extractor.dart:44` | `l10n.tiktokServiceStatus(response.statusCode)` | `ExtractionFailure(ExtractionFailureKind.tiktokServiceStatus, detail: '${response.statusCode}')` |
| `tiktok_extractor.dart:52` | `l10n.tiktokConnectionFailed(e.toString())` | `ExtractionFailure(ExtractionFailureKind.tiktokConnectionFailed, detail: e.toString())` |
| `tiktok_extractor.dart:57` | ternary producing `'TikTok: $message'` or `l10n.tiktokInvalidData` | `ExtractionFailure(ExtractionFailureKind.tiktokInvalidData, detail: message)` |
| `tiktok_extractor.dart:151` | `l10n.tiktokNoStreams` | `const ExtractionFailure(ExtractionFailureKind.tiktokNoStreams)` |
| `twitter_extractor.dart:43` | `l10n.xInvalidPost` | `const ExtractionFailure(ExtractionFailureKind.xInvalidPost)` |
| `twitter_extractor.dart:47` | `l10n.externalServicesDisabled` | `const ExtractionFailure(ExtractionFailureKind.externalServicesDisabled)` |
| `twitter_extractor.dart:56` | `l10n.xNoVideo` | `const ExtractionFailure(ExtractionFailureKind.xNoVideo)` |
| `youtube_extractor.dart:46` | `l10n.youtubeInvalidId` | `const ExtractionFailure(ExtractionFailureKind.youtubeInvalidId)` |
| `youtube_extractor.dart:127` | `l10n.youtubeLoadFailed(e.toString())` | `ExtractionFailure(ExtractionFailureKind.youtubeLoadFailed, detail: e.toString())` |
| `youtube_extractor.dart:137` | `l10n.youtubeNoPlayerData` | `const ExtractionFailure(ExtractionFailureKind.youtubeNoPlayerData)` |
| `youtube_extractor.dart:144` | `l10n.youtubeInvalidData(e.toString())` | `ExtractionFailure(ExtractionFailureKind.youtubeInvalidData, detail: e.toString())` |
| `youtube_extractor.dart:151` | `l10n.youtubePlaybackRejected(reason)` | `ExtractionFailure(ExtractionFailureKind.youtubePlaybackRejected, detail: reason)` |
| `youtube_extractor.dart:239` | ternary `l10n.youtubeCipherUnsupported` / `l10n.youtubeNoStreams` | ternary on the same `hasCipheredStreams` condition, producing `const ExtractionFailure(ExtractionFailureKind.youtubeCipherUnsupported)` or `const ExtractionFailure(ExtractionFailureKind.youtubeNoStreams)` |

The `tiktok_extractor.dart:57` site becomes:

```dart
    if (json['code'] != 0 || json['data'] == null) {
      final message = json['msg']?.toString();
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.tiktokInvalidData,
          detail: message,
        ),
      );
    }
```

The `'TikTok: '` prefix now lives in `describeExtractionFailure`, so behaviour is unchanged.

After this step, some extractors may no longer reference `l10n` on their failure paths but still need it for quality labels. Do **not** remove the parameter — `flutter analyze` will not complain about an unused method parameter, and removing it is phase 2.

- [ ] **Step 5: Render failures in the provider**

In `lib/providers/video_extractor_provider.dart`, add
`import '../l10n/extraction_failure_text.dart';` and change `_readableError` to take the localizations and branch before the `toString()` fallback:

```dart
  String _readableError(
    Object error,
    String fallbackErrorMessage,
    AppLocalizations l10n,
  ) {
    // Must come before the toString() fallback: an ExtractionException now
    // stringifies to its kind, which is not something to show a user.
    if (error is ExtractionException) {
      return describeExtractionFailure(error.failure, l10n);
    }
    var message = error.toString();
    while (message.startsWith('Exception:')) {
      message = message.substring('Exception:'.length).trim();
    }
    return message.isEmpty ? fallbackErrorMessage : message;
  }
```

Update its three call sites — `video_extractor_provider.dart:88`, `:163` and `:217` — to pass `l10n` as the third argument.

- [ ] **Step 6: Update the fixture tests**

`test/extractor_fixture_test.dart` asserts on English sentences where it checks failures. Change those assertions to check identity instead.

**This one will pass either way — convert it anyway.** The privacy-policy test at
`test/extractor_fixture_test.dart:28-39` asserts that `error.toString()` contains
`'disabled'`. After Step 3, `ExtractionException.toString()` returns
`ExtractionException(externalServicesDisabled)`, which still contains the
substring. The test would stay green while no longer testing what it claims to.
Rewrite it:

```dart
    expect(
      () => extractor.extract(url, l10n),
      throwsA(
        isA<ExtractionException>().having(
          (e) => e.failure.kind,
          'kind',
          ExtractionFailureKind.externalServicesDisabled,
        ),
      ),
    );
```

Run `grep -n "ExtractionException\|throwsA" test/extractor_fixture_test.dart` first and convert every match this way.

- [ ] **Step 7: Run the full suite**

Run: `flutter test`
Expected: PASS. Every previously passing test still passes, plus the two new ones from Step 1.

- [ ] **Step 8: Commit**

```bash
git add lib/services/extractors lib/providers/video_extractor_provider.dart test/
git commit -F - <<'MSG'
refactor(extractors): throw typed failures instead of translated text

Every extractor throw site now reports an `ExtractionFailure` rather than
a sentence that has already been translated, and the provider renders one
where it previously read the exception's message.

Twenty-one of the thirty-six localization keys the extractor layer used
leave the failure path. Extractor tests assert on failure identity, so a
reworded English string no longer breaks them.

`_readableError` branches on `ExtractionException` before its `toString()`
fallback. Without that branch the enum name would reach the user, so it
has a regression test.

The TikTok pass-through is preserved: when TikTok supplies its own `msg`,
that text is still shown verbatim, prefixed, rather than the generic
localized sentence.
MSG
```

---

### Task 3: Move `VideoPlatform`'s presentation getters

**Files:**
- Create: `lib/core/theme/platform_style.dart`
- Modify: `lib/models/video_platform.dart`
- Modify: `lib/views/downloads/widgets/active_download_card.dart`, `lib/views/downloads/widgets/completed_download_card.dart`, `lib/views/home/widgets/platform_badges.dart`, `lib/views/home/widgets/recent_links_card.dart`, `lib/views/home/widgets/url_input_card.dart`, `lib/views/home/widgets/video_result_card.dart` (imports only)
- Test: `test/architecture_test.dart` covers this in Task 4

**Interfaces:**
- Consumes: `VideoPlatform` from `lib/models/video_platform.dart`, `AppColors` from `lib/core/constants/app_colors.dart`.
- Produces: `extension PlatformStyle on VideoPlatform` with `Color get brandColor` and `IconData get icon`. Call sites keep their exact text.

- [ ] **Step 1: Create the extension**

Create `lib/core/theme/platform_style.dart`. Move the two getters out of `lib/models/video_platform.dart` verbatim — same switch arms, same `AppColors` and `Icons` values:

```dart
import 'package:flutter/material.dart';

import '../../models/video_platform.dart';
import '../constants/app_colors.dart';

/// Brand colour and icon for a platform.
///
/// These live in the theme layer rather than on the enum: a domain type
/// should not have to import Flutter's material library to describe itself.
/// Written as an extension so every call site keeps reading
/// `platform.brandColor` unchanged.
extension PlatformStyle on VideoPlatform {
  Color get brandColor => switch (this) {
    VideoPlatform.youtube => AppColors.youtube,
    VideoPlatform.tiktok => AppColors.tiktok,
    VideoPlatform.facebook => AppColors.facebook,
    VideoPlatform.twitter => AppColors.twitter,
    VideoPlatform.instagram => AppColors.instagram,
    VideoPlatform.generic => AppColors.primary,
  };

  IconData get icon => switch (this) {
    VideoPlatform.youtube => Icons.play_circle_fill_rounded,
    VideoPlatform.tiktok => Icons.music_note_rounded,
    VideoPlatform.facebook => Icons.facebook_rounded,
    VideoPlatform.twitter => Icons.flutter_dash_rounded,
    VideoPlatform.instagram => Icons.camera_alt_rounded,
    VideoPlatform.generic => Icons.link_rounded,
  };
}
```

Before writing, run `sed -n '1,80p' lib/models/video_platform.dart` and copy the exact values; do not retype them from this plan if they differ.

- [ ] **Step 2: Strip the enum**

In `lib/models/video_platform.dart`, delete the `brandColor` and `icon` getters and both imports (`package:flutter/material.dart` and `../core/constants/app_colors.dart`). Keep `displayName` — it returns brand names, is not translated, and needs no Flutter import.

- [ ] **Step 3: Run analyze to find the call sites**

Run: `flutter analyze`
Expected: FAIL with `The getter 'brandColor' isn't defined` / `'icon' isn't defined` across the six widget files listed above.

- [ ] **Step 4: Add the import to each call site**

Add `import '../../../core/theme/platform_style.dart';` to the two files under `lib/views/downloads/widgets/` and `lib/views/home/widgets/`, matching each file's existing relative-import depth. No other edit — the call sites' text is unchanged.

- [ ] **Step 5: Verify**

Run: `flutter analyze && flutter test`
Expected: `No issues found!` and the full suite passing. `grep -n "package:flutter" lib/models/video_platform.dart` must print nothing.

- [ ] **Step 6: Commit**

```bash
git add lib/core/theme/platform_style.dart lib/models/video_platform.dart lib/views/
git commit -F - <<'MSG'
refactor(models): move platform brand styling out of the enum

`VideoPlatform` imported Flutter's material library so it could expose a
brand colour and an icon, which put presentation data on a domain type.
Both getters move to an extension in the theme layer.

All twenty-four references were already inside `lib/views/`, so the call
sites are unchanged; each of the six widget files gains an import.
MSG
```

---

### Task 4: Architecture test

**Files:**
- Create: `test/architecture_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks; it reads the source tree from disk.
- Produces: nothing other tasks use.

- [ ] **Step 1: Write the test**

Create `test/architecture_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files under these directories, keyed by the directory they live in.
Map<String, List<File>> _sourcesByLayer() {
  final layers = <String, List<File>>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final path = entity.path.replaceAll(r'\', '/');
    // Generated localizations are not hand-written and are exempt.
    if (path.startsWith('lib/l10n/generated/')) continue;
    final relative = path.substring('lib/'.length);
    final layer = relative.contains('/')
        ? relative.substring(0, relative.indexOf('/'))
        : '.';
    (layers[layer] ??= []).add(entity);
  }
  return layers;
}

List<String> _importsOf(File file) => file
    .readAsLinesSync()
    .where((line) => line.trimLeft().startsWith('import '))
    .toList();

void _expectNoImports({
  required List<File> files,
  required List<String> forbidden,
  required String rule,
}) {
  final violations = <String>[];
  for (final file in files) {
    for (final import in _importsOf(file)) {
      for (final needle in forbidden) {
        if (import.contains(needle)) {
          violations.add('  ${file.path}: ${import.trim()}');
        }
      }
    }
  }
  expect(violations, isEmpty, reason: '$rule\n${violations.join('\n')}');
}

void main() {
  final layers = _sourcesByLayer();

  test('the lower layers do not depend on the upper ones', () {
    _expectNoImports(
      files: [
        ...?layers['services'],
        ...?layers['models'],
        ...?layers['core'],
      ],
      forbidden: ['views/', 'providers/'],
      rule: 'services, models and core must not import views or providers.',
    );
  });

  test('domain models carry no presentation dependency', () {
    // `package:flutter/foundation.dart` is allowed and used: DownloadTask is a
    // ChangeNotifier. It carries no widgets, rendering or theming. `material`
    // is what drags presentation into a domain type.
    _expectNoImports(
      files: layers['models'] ?? [],
      forbidden: ['package:flutter/material.dart', 'app_localizations'],
      rule: 'models must not import material or the generated localizations.',
    );
  });

  // Known debt, deliberately not asserted yet: `lib/services/extractors/`
  // still imports AppLocalizations, because quality labels are built there and
  // are still translated strings. Phase 2 of
  // docs/superpowers/specs/2026-08-27-extractor-decoupling-design.md moves
  // labels to typed descriptors; add the rule here once it lands.
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `flutter test test/architecture_test.dart`
Expected: PASS — Task 3 already removed the only violation.

If it fails, the reason string names every offending file and import; fix the source, not the test.

- [ ] **Step 3: Confirm the test can actually fail**

Temporarily add `import 'package:flutter/material.dart';` to `lib/models/download_options.dart`, run the test, and confirm it fails naming that file. Then remove the import. A guard that cannot fail is not a guard.

- [ ] **Step 4: Run the full check suite**

Run: `powershell -ExecutionPolicy Bypass -File .\tool\check_all.ps1`
Expected: `All checks passed`, 7/7 steps including the Android integration suite.

- [ ] **Step 5: Commit**

```bash
git add test/architecture_test.dart
git commit -F - <<'MSG'
test(architecture): pin the layer boundaries

Fails with a list of offending files and imports when services, models or
core reach up into views or providers, or when a domain model imports
Flutter's material library or the generated localizations.

The rule that extractors must not import AppLocalizations is deliberately
absent: quality labels are still built as translated strings there. A
comment records that as phase 2's work so the gap is documented rather
than silently missing.
MSG
```

---

## Self-Review

**Spec coverage.** Typed failures → Tasks 1 and 2. Rendering and the `toString()` trap → Task 2, Steps 1 and 5. `VideoPlatform` → Task 3. Architecture test, including the deliberately absent extractor rule → Task 4. Compatibility: no task touches `qualityLabel`, `sourceOptionId` or any persisted JSON, and the Global Constraints forbid it. Testing order in the spec — text mapping, then the trap, then fixture assertions, then the architecture test — matches Tasks 1 → 2 → 4.

**Placeholders.** None. Every code step carries the code. The two places that say "confirm before running" (the `tiktokServiceStatus` signature in Task 1 Step 4, and the enum values in Task 3 Step 1) are instructions to verify against the real source rather than gaps.

**Type consistency.** `ExtractionFailure(kind, {detail})` and `ExtractionFailureKind` are spelled identically in Tasks 1, 2 and 4. `describeExtractionFailure(failure, l10n)` has the same signature in its definition (Task 1 Step 4) and its two call sites (Task 2 Steps 1 and 5). `ExtractionException.failure` is introduced in Task 2 Step 3 and used in Steps 5 and 6. `PlatformStyle.brandColor` and `.icon` match the call sites they replace.

**One risk the plan cannot remove.** Task 2 is large because changing a constructor's type breaks all twenty-two call sites at once; they cannot land separately and still compile. The mapping table makes it mechanical, and `flutter analyze` finds anything missed.
