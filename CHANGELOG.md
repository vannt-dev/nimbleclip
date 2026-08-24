# Changelog

All notable changes to NimbleClip are documented in this file. This project
uses [Semantic Versioning](https://semver.org/) and release tags in the form
`vX.Y.Z`.

## [Unreleased]

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
