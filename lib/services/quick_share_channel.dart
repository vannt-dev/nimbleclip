import 'dart:async';

import 'package:background_downloader/background_downloader.dart' as bg;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The native side of Quick download: the share-sheet entry that downloads a
/// link without opening the app.
abstract interface class QuickShareChannel {
  /// Text shared to Quick download, including what arrived before anyone
  /// listened.
  Stream<String> get shares;

  /// Shows or hides the Quick download entry in the share sheet.
  Future<void> setTargetEnabled(bool enabled);

  /// Tells the user something while the app is not on screen.
  Future<void> showMessage(String message);

  /// Asks, while the app is on screen, to show notifications. Android hides
  /// the messages of an app that is behind another one without it.
  Future<void> requestNotifications();

  /// Lets go of the hold the share entry put on the process to keep it
  /// working. Called once the app's own download work holds it instead.
  Future<void> releaseKeepAlive();
}

/// Android's share-sheet entry. Every other platform has none, and each call
/// does nothing there.
class PlatformQuickShareChannel implements QuickShareChannel {
  const PlatformQuickShareChannel();

  static const _methods = MethodChannel('com.vannt.nimbleclip/quick_share');
  static const _events = EventChannel(
    'com.vannt.nimbleclip/quick_share_events',
  );

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static StreamController<String>? _shares;

  @override
  Stream<String> get shares {
    if (!_supported) return const Stream.empty();
    return (_shares ??= StreamController<String>.broadcast(
      onListen: _listen,
    )).stream;
  }

  static void _listen() {
    _events.receiveBroadcastStream().listen((value) {
      final text = value?.toString();
      if (text != null && text.isNotEmpty) _shares?.add(text);
    }, onError: (_) {});
    unawaited(_drainPending());
  }

  static Future<void> _drainPending() async {
    try {
      final pending = await _methods.invokeListMethod<String>('consumePending');
      for (final text in pending ?? const <String>[]) {
        _shares?.add(text);
      }
    } on PlatformException {
      // Nothing waiting.
    } on MissingPluginException {
      // A host without the share entry, such as a test.
    }
  }

  @override
  Future<void> setTargetEnabled(bool enabled) =>
      _call('setTargetEnabled', {'enabled': enabled});

  @override
  Future<void> showMessage(String message) =>
      _call('showMessage', {'message': message});

  @override
  Future<void> releaseKeepAlive() => _call('releaseKeepAlive');

  @override
  Future<void> requestNotifications() async {
    if (!_supported) return;
    try {
      final permissions = bg.FileDownloader().permissions;
      final status = await permissions.status(bg.PermissionType.notifications);
      if (status != bg.PermissionStatus.granted) {
        await permissions.request(bg.PermissionType.notifications);
      }
    } catch (_) {
      // Quick download still downloads; it only cannot say so.
    }
  }

  Future<void> _call(String method, [Map<String, Object?>? arguments]) async {
    if (!_supported) return;
    try {
      await _methods.invokeMethod<void>(method, arguments);
    } on PlatformException {
      // The share entry is an extra; the app works without it.
    } on MissingPluginException {
      // As above.
    }
  }
}
