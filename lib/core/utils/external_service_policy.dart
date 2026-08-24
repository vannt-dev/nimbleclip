import 'package:flutter/foundation.dart';

abstract interface class ExternalServiceAccess {
  bool get allowExternalServices;
}

class FixedExternalServiceAccess implements ExternalServiceAccess {
  @override
  final bool allowExternalServices;

  const FixedExternalServiceAccess(this.allowExternalServices);
}

/// Mutable application-scoped privacy policy injected into extractors.
class ExtractionPolicy extends ChangeNotifier implements ExternalServiceAccess {
  bool _allowExternalServices;

  factory ExtractionPolicy({bool allowExternalServices = true}) {
    return ExtractionPolicy._(allowExternalServices);
  }

  ExtractionPolicy._(this._allowExternalServices);

  @override
  bool get allowExternalServices => _allowExternalServices;

  void setAllowExternalServices(bool value) {
    if (_allowExternalServices == value) return;
    _allowExternalServices = value;
    notifyListeners();
  }
}
