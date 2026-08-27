# Decoupling the extractor layer from presentation — phase 1

Date: 2026-08-27
Status: approved, not yet implemented

## Problem

`AppLocalizations` reaches into `lib/services/extractors/`. Eight of the
thirteen files there take it as a parameter and read 36 keys from it. The
extraction engine — the part of the app that turns a URL into
`VideoMetadata` — depends on the generated Flutter localization class.

Two separate problems hide under that one symptom.

**Error messages.** Twenty-one of the 36 keys are failure text.
`ExtractionException` carries a `String` that has already been phrased and
translated, so extractor tests assert on English sentences and a wording change
breaks them. The failure has no identity a caller can branch on.

**Quality labels.** The other fifteen keys are display labels that end up in
`VideoQualityOption.label`. That field does three jobs at once:

1. display, in five widgets under `lib/views/`;
2. storage, as `DownloadTask.qualityLabel` in the history and receipt JSON
   written to `SharedPreferences`;
3. matching, at `download_provider.dart:247` and `:447`, where a retry or a
   duplicate check compares `task.qualityLabel` against `quality.label`.

A translated string acting as a storage key and a matching key is a latent bug:
switching language between an analysis and a retry breaks the comparison.
Impact is currently small because `sourceOptionId`, added in 1.3.0, is tried
first and the label is only the fallback for older history entries.

A third, smaller leak sits next to these: `lib/models/video_platform.dart`
imports `package:flutter/material.dart` so the enum can expose `brandColor` and
`icon`. A domain enum carries presentation data.

## Scope

This spec covers **phase 1 only**: typed failures, the `VideoPlatform` cleanup,
and an architecture test. Quality labels stay as they are.

Phase 2 — typed quality descriptors, storage and matching keyed on something
other than a translated string, and the migration for existing history — is a
separate spec and a separate change, deliberately deferred until 1.4.0 has been
in real use. It is the change that touches stored user data, so it should be
reviewable and revertable on its own.

### What phase 1 does not buy

`extract()` keeps its `AppLocalizations` parameter, because quality labels still
need it. Phase 1 therefore does **not** make the extractor layer extractable as
a pure Dart package. That remains phase 2's payoff.

What phase 1 does buy: 21 of the 36 keys leave the failure path, extractor tests
assert on failure identity instead of English prose, and `lib/models/` stops
depending on Flutter.

## Design

### Typed failures

A new `lib/services/extractors/extraction_failure.dart`:

```dart
enum ExtractionFailureKind {
  invalidLink,
  noDownloadStreams,
  externalServicesDisabled,
  linkAccessFailed,            // detail: underlying error
  facebookNoVideo,
  genericNoVideo,
  instagramInvalidPost,
  instagramLoginRequired,
  tiktokConnectionFailed,      // detail: underlying error
  tiktokInvalidData,
  tiktokNoStreams,
  tiktokServiceStatus,         // detail: HTTP status
  xInvalidPost,
  xNoVideo,
  youtubeCipherUnsupported,
  youtubeInvalidId,
  youtubeNoPlayerData,
  youtubeNoStreams,
  youtubeInvalidData,          // detail: underlying error
  youtubeLoadFailed,           // detail: underlying error
  youtubePlaybackRejected,     // detail: reason
}

class ExtractionFailure {
  const ExtractionFailure(this.kind, {this.detail});
  final ExtractionFailureKind kind;
  final String? detail;
}
```

`detail` is a single nullable `String` rather than a per-kind payload type. Six
kinds use it, each with exactly one substitution, and every substitution is
already a string at the call site. A sealed hierarchy would buy compile-time
proof that the right kinds carry a detail, at the cost of 21 classes; that is
not worth it here.

`ExtractionException` carries the failure instead of a message:

```dart
class ExtractionException implements Exception {
  const ExtractionException(
    this.failure, {
    this.diagnosticCode,
    this.attemptedStrategies = const [],
  });

  final ExtractionFailure failure;
  final String? diagnosticCode;
  final List<String> attemptedStrategies;
}
```

`diagnosticCode` and `attemptedStrategies` keep their current behaviour, so the
copyable diagnostics on Home are unaffected.

### Rendering a failure

A pure function in `lib/l10n/extraction_failure_text.dart`:

```dart
String describeExtractionFailure(ExtractionFailure failure, AppLocalizations l10n)
```

An exhaustive `switch` on `ExtractionFailureKind`, so adding a kind without
adding its text is a compile error rather than a blank message.

`VideoExtractorProvider` already receives `l10n` in `analyzeUrl`, `analyzeUrls`
and `retryBatchResult`, and already converts thrown objects to the `String` that
the UI reads. It calls `describeExtractionFailure` there. **No widget changes:**
`errorMessage` stays a `String` and every call site under `lib/views/` is
untouched.

### The `toString()` trap

`VideoExtractorProvider._readableError` currently does `error.toString()` and
strips `Exception:` prefixes. `ExtractionException.toString()` returns its
message today; once the message is gone, an unmodified `_readableError` would
surface an enum name like `ExtractionFailureKind.xNoVideo` to the user.

`_readableError` must branch on `ExtractionException` before falling back to
`toString()`. This is the most likely place for this change to go wrong quietly,
so it gets its own test first: an extractor that throws a known kind must
produce the localized sentence, in both English and Vietnamese.

### `VideoPlatform` styling

All 24 references to `brandColor` and `icon` are under `lib/views/`. None are
outside it. So both getters move to an extension in the presentation layer:

```dart
// lib/core/theme/platform_style.dart
extension PlatformStyle on VideoPlatform {
  Color get brandColor => ...;
  IconData get icon => ...;
}
```

Call sites keep their exact text (`task.platform.brandColor`); only an import is
added to the six widget files. `video_platform.dart` drops
`package:flutter/material.dart`.

`displayName` stays on the enum. It returns brand names, is not translated, and
pulls in no Flutter dependency.

### Architecture test

`test/architecture_test.dart` reads every file under `lib/` and asserts:

| Layer | May not import |
|---|---|
| `services/`, `models/`, `core/utils/` | `views/`, `providers/` |
| `models/` | `package:flutter/material.dart`, `AppLocalizations` |

Failures list every offending file and import, so the message is actionable
rather than a bare `false != true`.

The `models/` rule names `material` specifically, not Flutter as a whole:
`download_task.dart` imports `package:flutter/foundation.dart` because
`DownloadTask` is a `ChangeNotifier`, and that is intended. `foundation` carries
no widgets, rendering or theming; `material` is what drags presentation into a
domain type. `video_platform.dart` is the only file in `lib/models/` that
currently breaks the rule, and it also loses its `core/constants/app_colors.dart`
import once the getters move.

`services/` is not held to the `material` rule in this phase.
`background_download_service.dart` imports `package:flutter/widgets.dart` for
`Locale` alone, which is not worth routing around now.

The rule `services/extractors/` must not import `AppLocalizations` is
**deliberately absent**, because quality labels still need it. A comment in the
test records this as known debt and points at phase 2, so the gap is documented
rather than silently missing.

`lib/l10n/generated/` is excluded — it is generated, and `l10n.dart` legitimately
bridges to it.

## Compatibility

Nothing stored changes. `qualityLabel`, `sourceOptionId`, the history JSON and
the receipt JSON are untouched, so no migration is needed and an install
upgrading from 1.4.0 reads its existing data unchanged.

The `extract(url, l10n)` signature is unchanged.

## Testing

Written test-first, in this order:

1. `describeExtractionFailure` returns the right sentence for every kind, in
   English and Vietnamese, with the six detail substitutions applied.
2. `_readableError` renders an `ExtractionException` as its localized sentence
   and never as an enum name — the regression test for the trap above.
3. Existing extractor fixture tests move from asserting English sentences to
   asserting `failure.kind`.
4. The architecture test, which starts red on `video_platform.dart` and goes
   green once the extension lands.

`tool/check_all.ps1` must pass end to end, including the Android suite, before
the change is proposed.

## Files

| Change | Files |
|---|---|
| New | `extraction_failure.dart`, `extraction_failure_text.dart`, `platform_style.dart`, `architecture_test.dart` |
| Failure type | `base_extractor.dart`, `registry.dart`, 6 extractors |
| Rendering | `video_extractor_provider.dart` |
| Signature | `download_provider.dart` (`_refreshDownloadUrl`) |
| Styling | `video_platform.dart`, 6 widget files (import only) |
| Tests | `extractor_fixture_test.dart`, `widget_test.dart` |

## Risks

**The `toString()` trap** — covered by a dedicated test, written first.

**An extractor path with no test.** The fixture suite does not reach every
failure branch. Where a `throw` site has no test, the change is a mechanical
substitution of one constructor argument, and `describeExtractionFailure` being
an exhaustive switch means a missed kind cannot compile.

**Scope creep into phase 2.** Quality labels are explicitly out. If a change
starts to require touching `VideoQualityOption.label`, that is the signal to
stop and leave it for phase 2.
