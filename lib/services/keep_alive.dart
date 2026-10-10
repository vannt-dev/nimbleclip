// `dart.library.io` is the only usable discriminator, as for the audio
// converter: it also covers iOS and desktop, which the runtime
// `Platform.isAndroid` check in the native file turns away.
import 'keep_alive_stub.dart'
    if (dart.library.io) 'keep_alive_android.dart'
    as impl;

/// Asks the system to leave the app's process alone while it has downloads to
/// finish and is off screen.
///
/// A transfer handed to the system carries on by itself. What needs the app is
/// the rest: joining the parts of a video, converting audio to MP3, fetching a
/// stream segment by segment, rendering a slideshow. Android freezes or ends a
/// background process that shows nothing for its work, so such a download
/// stopped short until the app was opened again.
abstract interface class ProcessKeepAlive {
  /// Whether this platform has anything to ask. When false, [start] and
  /// [stop] do nothing and need not be called.
  bool get isSupported;

  /// Shows a notification with [title] and [text] and keeps the process
  /// working. Safe to call again while it is on.
  Future<void> start({required String title, required String text});

  Future<void> stop();
}

class NoProcessKeepAlive implements ProcessKeepAlive {
  const NoProcessKeepAlive();

  @override
  bool get isSupported => false;

  @override
  Future<void> start({required String title, required String text}) async {}

  @override
  Future<void> stop() async {}
}

/// The keeper for the current platform.
ProcessKeepAlive createProcessKeepAlive() => impl.createProcessKeepAlive();
