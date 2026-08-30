# Changelog

All notable changes to NimbleClip are documented in this file. This project
uses [Semantic Versioning](https://semver.org/) and release tags in the form
`vX.Y.Z`.

## [Unreleased]

- Fixed a shared Facebook album link returning only its first photo. Facebook
  serves an anonymous visitor no gallery at all, so the whole set comes from
  the fallback service, and that step was reached only by a post permalink. A
  link copied from the Share action, such as `facebook.com/share/<token>/`,
  never redirects to one, so it was left with the single Open Graph image.

## [1.5.0] - 2026-08-28

- Added support for Instagram story and highlight links, which were previously
  rejected as unrecognised. These are served only through the external
  fallback service: the page Instagram returns for one without a login has no
  media in it, so the feature is unavailable when external services are turned
  off, and says so rather than failing silently.
- Added a video picker. A post carrying several videos previously downloaded
  all of them and listed each as a row of text, with no way to see what they
  were or leave any out. Videos now use the same thumbnail grid as photos,
  with multi-select, select-all, and playback to preview one before choosing.
- Fixed a post holding both photos and video offering no way to pick the
  video. Photos were ranked as though "Original" meant 2160p, so they
  outranked every video and the video tab came up with nothing selected. Worst
  on X, where photos always outranked the real resolutions its videos carry.
- Fixed the download notification growing with the title. A long post name
  wrapped it to four lines and its action to a line of its own, leaving the
  notice standing over the page it was reporting on.
- Fixed the app name and the link-field heading running off the side of a
  narrow screen, which longer Vietnamese wording made more likely.
- Changed the videos of a multi-video post to be numbered. They were all
  labelled "MP4 (Original quality)", which on a highlight meant a column of
  identical rows.
- Changed a text-less X post to be titled with the author's handle alone, such
  as `@example`, instead of the "Post by" wording that preceded it.
- Changed the extractors to describe a download option with a typed descriptor
  instead of building its text, so the layer no longer needs a locale.
  Download history keeps storing the rendered name, so entries written by
  earlier versions read back unchanged.

## [1.4.0] - 2026-08-27

- Fixed a startup failure that replaced the whole app with an error screen
  because the extraction policy, a change notifier, was registered as a plain
  value provider.
- Added a Direct Share target so NimbleClip appears in the top row of the
  Android share sheet instead of only in the full application list.
- Fixed the Android launcher activity declaring an empty task affinity, so
  repeated shares stay in one NimbleClip task and instance.
- Fixed the link field opening the keyboard in its password layout, which
  happened because suggestions were disabled.
- Changed the link field to a single line with one placeholder, so a long link
  scrolls sideways instead of stretching the card downwards.
- Fixed numeric HTML entities such as `&#x2026;` appearing verbatim in
  extracted titles.
- Fixed the download gateway never being released when the download provider is
  disposed, which left the native update stream claimed for the process.
- Added widget coverage for the downloads, settings, image picker, and player
  screens.
- Changed Facebook and Instagram image scanning to run on a background isolate
  for large documents, so decoding and walking a post's inline JSON no longer
  blocks the UI thread during analysis.
- Changed HTML entity decoding to a single pass. It previously copied the whole
  string seven times, which was measurable on the multi-megabyte inline scripts
  the Facebook parser feeds it.
- Changed download receipts to be held in memory instead of being re-read,
  rebuilt and re-encoded from preferences after every completed download.
- Changed download history persistence to hand over already-serialized records,
  removing a full clone of every task on each save.
- Changed analysis history to be rewritten only when it holds legacy entries
  that still need migrating, instead of re-encoding and writing preferences on
  every app start.
- Changed extractor and helper regular expressions to compile once instead of
  on every call; the Instagram carousel loop rebuilt seven of them per slide.
- Changed the active download card to keep its thumbnail and title out of the
  progress rebuild, which ran about ten times a second per transfer.
- Added a decode-width cap to the full-screen image previews and lowered the
  global image cache budget, bounding the memory a large post photo can use.
- Added stable list keys to download entries so inserting a task no longer
  reuses list elements for a different task.
- Fixed the Home image preview not sending the extractor's request headers,
  which broke previews for sources whose CDN requires a Referer.

## [1.3.0] - 2026-08-25

- Added native mobile download recovery after app process termination, with
  Android DownloadWorker and iOS URLSession state restored into app history.
- Added bounded batch analysis (20 links, three concurrent extractors),
  per-link quality selection, retry, cancellation, and richer diagnostics.
- Added compact analysis history migration so expiring signed media URLs are
  not retained in local preferences.
- Hardened the Web YouTube fallback for `signatureCipher` and throttling `n`
  transforms using a restricted parser that never evaluates remote JavaScript.
- Added Android background-worker integration coverage and an iOS CI build that
  verifies the embedded Share Extension and App Group entitlements.
- Added URL autofill hints, live-region accessibility updates, and expanded
  diagnostics with platform, duration, timestamp, and app version details.
- Added pull-to-refresh on Home to clear the previous result, return to the URL
  input, and start another analysis.

## [1.2.0] - 2026-08-24

- Added complete image, video, and mixed-media extraction for public Facebook,
  Instagram, TikTok, X, and compatible Open Graph posts, including full
  Facebook galleries and X photo sets.
- Added batch selection and download controls for multi-image posts while
  keeping one selectable quality per video stream.
- Standardized compact platform-prefixed filenames, including `facebook_<uuid>`,
  `instagram_<uuid>`, `tiktok_<uuid>`, and `x_<uuid>`.
- Improved extractor resilience with retry handling, provider fallbacks, and
  selection of the richest Facebook image result across page strategies.
- Added a privacy control for external extraction services with localized
  disclosure that public post URLs may be sent to those services.
- Added configurable download concurrency from one to five simultaneous
  transfers.
- Added safe post-export cache cleanup on Android. NimbleClip now persists the
  MediaStore URI so Gallery media remains available to open and share after the
  app-local copy is removed.
- Shortened the batch action label to `Download (n)` / `Tải xuống (n)` to avoid
  wrapping on smaller screens.
- Added extractor fixtures, MediaStore URI integration coverage, and opt-in live
  smoke tests for public image and video posts.
- Refactored download coordination into reusable queue, history repository, and
  platform file-action services, with explicit download options shared across
  call sites.
- Refactored Facebook and Instagram extraction into dedicated page parsers and
  injectable fallback clients, and replaced mutable global privacy state with
  an injected application policy.
- Consolidated media format, URL, quality construction, and batch-selection
  logic, and removed duplicate download cards and settings selection tiles.

## [1.1.1] - 2026-08-23

- Hardened native downloads with media signature inspection, real video
  playback validation, extension correction, and clean restart behavior when a
  server mishandles HTTP range requests.
- Switched downloaded files to compact UUID-style names and added persistent
  download receipts so completed local or Gallery copies are detected even
  after visible history is cleared.
- Added confirmation before downloading an existing file again and prevented
  duplicate tasks while the same source option is queued, downloading, or
  paused.
- Fixed long-lived download notifications so they close when every task in the
  batch reaches a terminal state.
- Improved open and share actions with explicit missing-file, unsupported-app,
  and failure feedback; stale local files are now reconciled with history.
- Removed the misleading Gallery action for audio while retaining Gallery
  export for videos and images.
- Added a single Windows verification command covering formatting, analysis,
  Flutter and Node tests, Web release build, emulator setup, fixture lifecycle,
  and Android integration tests.
- Added fixture-server identity checks and Android emulator integration tests
  to continuous integration.

## [1.1.0] - 2026-08-21

- Added public Instagram and TikTok image-post support, including carousel
  previews, select-all controls, and multi-image downloads.
- Added a shared three-transfer download queue, stable retry matching,
  serialized history persistence, and per-task progress updates.
- Improved image selection performance with lazy thumbnail rendering and
  reduced application-wide widget rebuilds during downloads.
- Improved extractor and storage performance with connection reuse,
  extensionless-media header probes, cached SnapInsta tokens, and asynchronous
  filesystem traversal.
- Refreshed launcher icons and splash screens across Android, iOS, Web, macOS,
  and Windows, including Android round and themed icons.
- Hardened the Web proxy with route method allowlists and bounded rate-limit
  state, and expanded regression and security coverage.
- Added reusable PowerShell launch and branding generators plus synchronized
  release and contributor documentation.
- Automated version-bump releases so signed artifacts are published only after
  every CI quality and platform-build gate succeeds.

## [1.0.0] - 2026-08-19

- Introduced public video and audio extraction for supported social platforms.
- Added resumable downloads, local playback, sharing, and gallery export.
- Added English and Vietnamese localization with an in-app language selector.
- Added Android, iOS, desktop, and browser project targets.
