# The public core

What NimbleClip is built with when the private core is not there.

The app is written against `lib/services/extractors`, a git submodule of the
private repository `vannt-dev/nimbleclip-core`. This folder holds the same
names with less behind them, and `dart run tool/use_public_core.dart` copies
it into the empty `lib/services/extractors` of a checkout without access.

| File | In the public core |
| --- | --- |
| `base_extractor.dart`, `extraction_failure.dart` | The interface and the failure kinds, as in the full core |
| `registry.dart`, `generic_extractor.dart` | One extractor: a link to a media file, or a page that names its media in Open Graph or Twitter Card metadata. A link to a site the full core reads by name is answered with "no downloadable media" |
| `youtube_playlist.dart` | The types the app uses; no playlist is read |
| `streams/stream_fetcher.dart` | A file fetched in one request, and the length probe the parts transfer uses |
| `streams/hls_fetcher.dart`, `streams/dash_fetcher.dart`, `streams/hls_decryptor.dart` | Stand-ins that report an unreadable stream; the extractor above never offers one |
| `android/kotlin/…/PublicCoreEncoders.kt` | The Kotlin names `MainActivity` is written against (slideshow, stream join, segment cipher, MP3), each reporting that it is not here |

It stays in step with the app because it is analysed with it: the files sit at
the same depth as the real core, so their relative imports are the same in
both places. `test/public_core_test.dart` tests it, and CI builds the app with
it for Android and iOS.

A change to what the app needs from its core has to be made in both.
