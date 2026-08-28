# Typed quality descriptors — extractor decoupling phase 2

Date: 2026-08-27
Status: approved, in progress
Follows: `2026-08-27-extractor-decoupling-design.md`

## What changed since phase 1's spec

Phase 1's spec sketched this phase as "typed quality descriptors, and moving
storage and matching off a translated string", with a migration for existing
history. Reading the code closely, **the migration is not needed and should not
be done.**

`DownloadTask.qualityLabel` is written in `DownloadProvider.startNewDownloads`,
which already receives `l10n`. So if `VideoQualityOption` carries a descriptor,
the provider renders it to a string at that moment and stores exactly what it
stores today. Persistence is unchanged byte for byte. No migration, no risk to
stored user data.

The prize phase 1 could not reach — dropping `AppLocalizations` from
`extract()`, which is what makes the extractor layer extractable as a package —
is reached anyway.

### On the language-switch quirk

Phase 1's spec called the label-based matching "a latent bug". That was
overstated and is corrected here. Both `_matchesSelection` and
`_refreshDownloadUrl` try `sourceOptionId` first, and that field has existed
since 1.3.0. Label comparison is only the fallback for entries written by 1.2.0
or earlier. The exposure is: downloaded on ≤1.2.0, changed language, then
retried — narrow, and shrinking with every release.

It is not worth a migration of stored data. Left as is.

## Design

### The descriptor

`VideoQualityOption.label` changes from a translated `String` to a
`QualityDescriptor`. Twenty-six assignment sites across six extractors reduce to
ten variants:

| Variant | Renders as | Sites |
|---|---|---|
| `ImageIndex(index)` | `Image {n}` | 9 |
| `Hd720()` | `HD 720p (High quality)` | 1 |
| `Sd480()` | `SD 480p (Standard)` | 1 |
| `OriginalVideo()` | `Video (Original)` | 3 |
| `OriginalMp4()` | `MP4 (Original quality)` | 4 |
| `OriginalAudio()` | `Audio (Original)` | 2 |
| `EmbeddedVideo()` | `Embedded video (Web)` | 1 |
| `AudioMp3(title)` | `MP3 audio ({title})` | 1 |
| `AudioM4a(kbps)` | `M4A audio ({kbps} kbps)` | 2 |
| `VideoWithAudio(quality)` | `{quality} (Video + Audio)` | 2 |
| `WatermarkedVideo(quality, watermarked)` | `{quality} (No watermark)` / `(With TikTok watermark)` | 3 |
| `VideoBitrate(quality, kbps)` | `{quality} ({kbps} kbps)` | 1 |

`describeQuality(descriptor, l10n)` renders one, as an exhaustive switch, the
same shape as `describeExtractionFailure` from phase 1.

`VideoBitrate` is new text. X's option label is currently built as
`'$quality ($kbps kbps)'` — a hardcoded string that has never been translated.
Giving it a descriptor translates it, so this phase fixes a small gap rather
than only moving code.

### Rendering

- **UI**: five widgets read `option.label`; they call `describeQuality`.
- **Persistence**: `DownloadProvider.startNewDownloads` renders the descriptor
  and stores the resulting string in `DownloadTask.qualityLabel`, unchanged in
  shape and content from today.
- **`QualityHelper.rankOf`** currently falls back to `parseHeight(option.label)`.
  With a typed label there is no string to parse, so the fallback is dropped and
  `parseHeight(option.quality)` stands alone. That is the field the fallback
  existed to back up, and every site sets it.

### A correction folded in

Three sites assign a **translated string to `quality`**, not to `label`:
`instagram_extractor.dart:277`, `instagram_extractor.dart:480` and
`tiktok_extractor.dart:94`, all for images, all overriding
`VideoQualityOption.image`'s `quality = 'Original'` default with `Image {n}`.

`quality` is documented as `// e.g. "1080p", "720p", "480p", "Audio"` and feeds
`QualityHelper.parseHeight`, so display text there is wrong. It is harmless
today only by accident — `parseHeight('Image 3')` finds no resolution and
returns null. The fix is to delete the three overrides and let the correct
default stand.

### The payoff

With no label needing translation, `AppLocalizations` leaves the extractor
layer entirely:

- `BaseVideoExtractor.extract(String url)` — no `l10n` parameter
- `ExtractorRegistry.extract(String rawUrl)` — same
- every extractor file stops importing the generated localizations

`test/architecture_test.dart` gains the rule phase 1 deliberately left out:
`lib/services/extractors/` must not import `app_localizations`.

## Compatibility

Nothing persisted changes. `qualityLabel`, `sourceOptionId`, the history JSON
and the receipt JSON keep their current shape and content, so an install
upgrading from 1.4.0 reads its data unchanged and no migration runs.

`VideoQualityOption.toJson`/`fromJson` do change, since `label` is now typed.
That question was checked before writing any code, and the answer is more
interesting than expected:

`VideoMetadata.toJson()` **does** serialize its qualities, and analysis history
written before the 1.3.0 compact migration stores a whole `VideoMetadata` under
a `metadata` key. So legacy preferences on a real device **can** contain
serialized `VideoQualityOption` objects whose `label` is a translated string.

There is exactly one reader: the legacy branch of
`AnalysisHistoryEntry.fromJson`, which passes the decoded metadata to
`fromMetadata` — and that takes only `originalUrl`, `title`, `coverUrl`,
`platform` and `analyzedAt`. **The qualities are parsed and immediately
discarded.**

So the requirement is narrow: `VideoQualityOption.fromJson` must not throw on a
legacy string label. It gets an eleventh variant, `LiteralLabel(text)`, which
renders its stored text verbatim. It is produced only by deserialization, never
by an extractor, and the value never reaches a screen because the entry that
carries it drops its qualities on the way in.

This does not change the conclusion: nothing an extractor produces is persisted,
and no migration runs.

## Testing

1. `describeQuality` renders every variant in English and Vietnamese, with
   substitutions applied.
2. Extractor fixture tests assert descriptor identity instead of English text.
3. A test that a started download still stores a rendered string in
   `qualityLabel`, proving persistence did not change shape.
4. The architecture test's new extractor rule.

`tool/check_all.ps1` must pass end to end before the change is proposed.

## Risks

**The `toJson` question above is the one real unknown.** It is checked first,
before any code moves.

**`rankOf` losing its label fallback.** Every option sets `quality`, and after
the correction above every `quality` is a technical string, so the fallback has
nothing left to catch. Covered by the existing `quality_helper_test.dart`.
