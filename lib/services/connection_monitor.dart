import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

/// Says whether the device is on a connection that is not billed by the byte:
/// Wi-Fi or a cable.
abstract interface class ConnectionMonitor {
  Future<bool> isUnmetered();

  /// The answer of [isUnmetered] each time the connection changes.
  Stream<bool> get unmeteredChanges;
}

class PlatformConnectionMonitor implements ConnectionMonitor {
  PlatformConnectionMonitor({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  /// A VPN reports the network underneath it alongside itself, so one riding
  /// on Wi-Fi still counts; one that names nothing underneath does not.
  @visibleForTesting
  static bool unmetered(List<ConnectivityResult> results) =>
      results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet);

  @override
  Future<bool> isUnmetered() async {
    // A browser does not say what it is connected through.
    if (kIsWeb) return true;
    try {
      return unmetered(await _connectivity.checkConnectivity());
    } catch (_) {
      // Not knowing must not strand every download in the queue.
      return true;
    }
  }

  @override
  Stream<bool> get unmeteredChanges => kIsWeb
      ? const Stream<bool>.empty()
      : _connectivity.onConnectivityChanged.map(unmetered);
}
