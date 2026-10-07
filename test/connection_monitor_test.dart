import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/connection_monitor.dart';

void main() {
  test(
    'Wi-Fi and a cable are unmetered; mobile data and no connection are not',
    () {
      const unmetered = PlatformConnectionMonitor.unmetered;

      expect(unmetered([ConnectivityResult.wifi]), isTrue);
      expect(unmetered([ConnectivityResult.ethernet]), isTrue);
      // A VPN riding on Wi-Fi reports both.
      expect(
        unmetered([ConnectivityResult.vpn, ConnectivityResult.wifi]),
        isTrue,
      );
      expect(unmetered([ConnectivityResult.mobile]), isFalse);
      expect(
        unmetered([ConnectivityResult.vpn, ConnectivityResult.mobile]),
        isFalse,
      );
      expect(unmetered([ConnectivityResult.none]), isFalse);
      expect(unmetered(const []), isFalse);
    },
  );
}
