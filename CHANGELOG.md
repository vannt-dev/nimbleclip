# Changelog

All notable changes to NimbleClip are documented in this file. This project
uses [Semantic Versioning](https://semver.org/) and release tags in the form
`vX.Y.Z`.

## [Unreleased]

## [1.6.0] - 2026-09-03

- Added a slideshow option to TikTok photo posts on Android: the post's images
  and its music are rendered on the device into one 1080x1920 MP4, three
  seconds an image, instead of arriving as a folder of pictures and a separate
  audio file. The option carries no download URL — there is nothing to fetch —
  so it is split off ahead of the download queue and rendered instead, and the
  finished file enters history as a file that already exists.
- The music is transcoded to AAC before a single frame is muxed, because
  `MediaMuxer` refuses both MP3 in an MP4 and any track added after the file
  has been started. A track that will not decode therefore cannot damage the
  picture: the render carries on and produces a silent video with a note on it,
  since a slideshow without music is usable and a failed one is not.
- The option is offered only where it can actually run. The renderer's own
  runtime check is what decides — a Dart conditional import cannot tell Android
  from iOS, since both have `dart.library.io` — so iOS, desktop and Web see no
  slideshow row at all rather than one that fails when tapped.
- A slideshow render now reports its progress and can be cancelled. The encode
  runs outside the download queue, so neither the progress bar nor the Cancel
  button reached it: a render showed nothing for its whole duration and then
  jumped to done, and cancelling appeared to work before the finished encode
  overwrote the row back to completed. The encoder reports once per image and
  checks for a cancellation between images, so a tap stops it within one image
  and leaves no half-written file behind.
- Fixed a slideshow retried after the app restarted being fetched instead of
  re-rendered. The source a render was built from is held in memory while a
  failed task is written to history, so on the next launch Retry fell through
  to the download path with an empty URL. The retry now re-extracts the post to
  recover the source.
- Upgraded `chewie` and `video_player_android` to their latest patch releases.

## [1.5.2] - 2026-09-01

- Added a distinct message for a Facebook post Facebook gates as 18+. Such a
  post can be public and still be withheld from anyone not logged in, so the
  old wording — "make sure it is public" — sent the reader to check the one
  thing that was already fine. The gate is recognised by the route Facebook
  names in the document; the sentence a reader sees is drawn by script and
  never reaches the HTML.
- Fixed every Facebook reel and share link failing outright. Facebook began
  answering 400 to a request that claims a browser User-Agent but omits the
  `Sec-Fetch-*` headers a browser always sends on a top-level navigation, so
  `/reel/<id>/`, `/share/r/<token>/` and `/share/p/<token>/` were refused
  before the redirect to the post could even happen, and every extraction
  strategy came back empty. Page requests now carry those headers; the JSON
  calls to the fallback service and the HEAD probe for a direct media file,
  which are not navigations, do not.
- Fixed, as a side effect of the same change, Instagram's embed-player
  strategy coming back without its `contextJSON` payload. Instagram was
  serving a different, larger page to a request that omitted the navigation
  headers; the payload is there on all three repeats once they are sent.
- Stopped a Facebook share link downloading the page it points at twice.
  Expanding the link already fetched that page in full, and the first
  extraction strategy then asked for the very same URL again — measured at
  roughly 64 KB and 0.8 s of pure duplication per link. The expansion now
  hands the response on, and only when it can stand in for a fresh request:
  a body that is empty, or a response that failed, is still refetched.

## [1.5.1] - 2026-08-30

- Fixed a shared Facebook album link returning only its first photo. Facebook
  serves an anonymous visitor no gallery at all, so the whole set comes from
  the fallback service, and that step was reached only by a post permalink. A
  link copied from the Share action, such as `facebook.com/share/<token>/`,
  never redirects to one, so it was left with the single Open Graph image.
- Fixed the same shortfall on a group post addressed as
  `/groups/<id>/permalink/<id>/`. A group names its posts two ways and only
  the other one was recognised.
- Added a note on a Facebook result when it may be holding fewer photos than
  the post does. One photo used to mean either "this post has one photo" or
  "the service that lists the rest is unavailable", with no way to tell which.
  The note appears only when the shortfall is knowable — external services
  turned off, or a service that did not answer — and says which of the two it
  is. A post that really holds one photo says nothing, and nothing becomes an
  error: whatever was extracted stays downloadable.
- Fixed comment stickers being listed among a Facebook post's photos. A real
  five-photo album came through as seven, the last two being the same sticker
  at two sizes.
- Fixed sharing a link into the app while the downloads tab was open leaving
  the app on that tab. The link was analysed either way, out of sight, so the
  share looked as though it had done nothing.
- Changed the recent links section to stay folded away until it is opened, its
  heading carrying the count. Five entries laid out flat sat between the link
  field and the result. Each entry also gains a copy button, which the section
  previously had no way to do at all.
- Added swiping between a post's photos, and between its videos, in the viewer.
  Reaching the next one meant closing the current one and tapping it; the
  viewer now carries the whole set of that kind, with a position counter.
  Photos stay with photos and videos with videos.

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
