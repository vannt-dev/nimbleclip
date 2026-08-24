import 'package:flutter/material.dart';

import '../core/utils/quality_helper.dart';
import '../core/utils/url_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/video_metadata.dart';
import '../services/extractors/registry.dart';

class VideoExtractorProvider extends ChangeNotifier {
  VideoExtractorProvider({ExtractorRegistry? extractorRegistry})
    : _extractorRegistry = extractorRegistry ?? ExtractorRegistry();

  final ExtractorRegistry _extractorRegistry;
  VideoMetadata? _metadata;
  VideoQualityOption? _selectedQuality;
  bool _isAnalyzing = false;
  String? _errorMessage;
  String _currentUrl = '';

  /// Guards against a slow earlier analysis overwriting a newer one when the
  /// user edits the URL and re-submits before the first request returns.
  int _requestSequence = 0;

  VideoMetadata? get metadata => _metadata;
  VideoQualityOption? get selectedQuality => _selectedQuality;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  String get currentUrl => _currentUrl;
  bool get hasResult => _metadata != null;

  Future<bool> analyzeUrl(
    String url, {
    String preferredQuality = 'Highest',
    required AppLocalizations l10n,
  }) async {
    final cleanUrl = UrlHelper.extractCleanUrl(url);
    if (!UrlHelper.isValidVideoUrl(cleanUrl)) {
      _errorMessage = l10n.invalidVideoUrl;
      _metadata = null;
      _selectedQuality = null;
      notifyListeners();
      return false;
    }

    final sequence = ++_requestSequence;
    _isAnalyzing = true;
    _errorMessage = null;
    _metadata = null;
    _selectedQuality = null;
    _currentUrl = cleanUrl;
    notifyListeners();

    try {
      final metadata = await _extractorRegistry.extract(cleanUrl, l10n);
      if (sequence != _requestSequence) return false;

      _metadata = metadata;
      _selectedQuality =
          QualityHelper.bestMatch(metadata.qualities, preferredQuality) ??
          metadata.bestQuality;
      _isAnalyzing = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (sequence != _requestSequence) return false;
      _isAnalyzing = false;
      _errorMessage = _readableError(e, l10n.unableToAnalyze);
      notifyListeners();
      return false;
    }
  }

  /// Strips the `Exception:` prefixes Dart adds so the user sees the message the
  /// extractor actually wrote.
  String _readableError(Object error, String fallbackErrorMessage) {
    var message = error.toString();
    while (message.startsWith('Exception:')) {
      message = message.substring('Exception:'.length).trim();
    }
    return message.isEmpty ? fallbackErrorMessage : message;
  }

  void selectQuality(VideoQualityOption quality) {
    _selectedQuality = quality;
    notifyListeners();
  }

  void clear() {
    _requestSequence++;
    _metadata = null;
    _selectedQuality = null;
    _isAnalyzing = false;
    _errorMessage = null;
    _currentUrl = '';
    notifyListeners();
  }
}
