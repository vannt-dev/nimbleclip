import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'keep_alive.dart';

/// An Android foreground service, `KeepAliveService`.
///
/// The system refuses one started while the app is in the background, so it
/// is started when the work begins, which is when the user asks for it.
class AndroidProcessKeepAlive implements ProcessKeepAlive {
  const AndroidProcessKeepAlive();

  static const _channel = MethodChannel('com.vannt.nimbleclip/keep_alive');

  @override
  bool get isSupported => true;

  @override
  Future<void> start({required String title, required String text}) async {
    try {
      await _channel.invokeMethod<bool>('start', {
        'title': title,
        'text': text,
      });
    } on PlatformException {
      // Not having it is how the app worked before; the download goes on.
    } on MissingPluginException {
      // A build without the service, such as a test host.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      // Nothing to stop.
    } on MissingPluginException {
      // As above.
    }
  }
}

ProcessKeepAlive createProcessKeepAlive() => !kIsWeb && Platform.isAndroid
    ? const AndroidProcessKeepAlive()
    : const NoProcessKeepAlive();
