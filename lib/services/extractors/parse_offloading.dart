import 'package:flutter/foundation.dart';

/// Size at which a page is parsed on a background isolate instead of inline.
///
/// Extractor parsing is the heaviest synchronous work the app does: a Facebook
/// or Instagram post embeds its data as inline `<script type="application/json">`
/// blocks that together run to several megabytes, and every one of them is
/// entity-decoded, `jsonDecode`d and walked. On the UI isolate that is dropped
/// frames; a 20-link batch does it twenty times.
///
/// Below this size the work finishes well inside a frame, and handing it to an
/// isolate would cost more in spawn and copying than it saves.
const int parseOffloadThresholdBytes = 256 * 1024;

/// Runs [parser] on a background isolate when [source] is large enough to be
/// worth the hand-off, and inline otherwise.
///
/// [parser] must be a top-level or static function: closures cannot cross an
/// isolate boundary. On the Web `compute` runs the callback inline, because
/// browsers give Dart no second isolate to run it on — the threshold still
/// avoids the needless indirection there.
Future<R> parseOffMainIsolate<R>(
  R Function(String source) parser,
  String source, {
  String? debugLabel,
}) {
  if (source.length < parseOffloadThresholdBytes || kIsWeb) {
    return SynchronousFuture<R>(parser(source));
  }
  return compute(parser, source, debugLabel: debugLabel);
}
