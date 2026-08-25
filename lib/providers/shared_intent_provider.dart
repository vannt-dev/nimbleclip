import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/utils/url_helper.dart';

class SharedIntentProvider extends ChangeNotifier with WidgetsBindingObserver {
  SharedIntentProvider() {
    WidgetsBinding.instance.addObserver(this);
    _initialize();
  }

  static const _methods = MethodChannel('com.vannt.nimbleclip/shared_intent');
  static const _events = EventChannel(
    'com.vannt.nimbleclip/shared_intent_events',
  );
  StreamSubscription<dynamic>? _subscription;
  String? _pendingText;

  String? get pendingText => _pendingText;

  void _initialize() {
    _subscription = _events.receiveBroadcastStream().listen(
      (value) => _accept(value?.toString()),
      onError: (_) {},
    );
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      _accept(await _methods.invokeMethod<String>('consumeSharedText'));
    } catch (_) {
      // Desktop and Web intentionally have no native share receiver.
    }
  }

  void _accept(String? text) {
    if (text == null) return;
    if (UrlHelper.extractUrls(text).isEmpty) return;
    _pendingText = text;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_poll());
  }

  String? consume() {
    final value = _pendingText;
    _pendingText = null;
    return value;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final subscription = _subscription;
    if (subscription != null) unawaited(subscription.cancel());
    super.dispose();
  }
}
