import 'package:flutter/material.dart';

import '../core/utils/quality_helper.dart';
import '../core/utils/url_helper.dart';
import '../l10n/generated/app_localizations.dart';
import '../models/video_metadata.dart';
import '../services/extractors/registry.dart';
import '../l10n/extraction_failure_text.dart';
import '../services/extractors/base_extractor.dart';

class VideoExtractorProvider extends ChangeNotifier {
  VideoExtractorProvider({ExtractorRegistry? extractorRegistry})
    : _extractorRegistry = extractorRegistry ?? ExtractorRegistry();

  final ExtractorRegistry _extractorRegistry;
  VideoMetadata? _metadata;
  VideoQualityOption? _selectedQuality;
  bool _isAnalyzing = false;
  String? _errorMessage;
  String _currentUrl = '';
  String? _diagnosticCode;
  List<String> _attemptedStrategies = const [];
  List<BatchAnalysisResult> _batchResults = const [];
  Duration? _lastAnalysisDuration;
  DateTime? _lastAnalyzedAt;

  /// Guards against a slow earlier analysis overwriting a newer one when the
  /// user edits the URL and re-submits before the first request returns.
  int _requestSequence = 0;
  static const int maximumBatchUrls = 20;
  static const int maximumParallelAnalyses = 3;

  VideoMetadata? get metadata => _metadata;
  VideoQualityOption? get selectedQuality => _selectedQuality;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  String get currentUrl => _currentUrl;
  bool get hasResult => _metadata != null;
  String? get diagnosticCode => _diagnosticCode;
  List<String> get attemptedStrategies =>
      List.unmodifiable(_attemptedStrategies);
  List<BatchAnalysisResult> get batchResults =>
      List.unmodifiable(_batchResults);
  Duration? get lastAnalysisDuration => _lastAnalysisDuration;
  DateTime? get lastAnalyzedAt => _lastAnalyzedAt;

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
    _diagnosticCode = null;
    _attemptedStrategies = const [];
    _batchResults = const [];
    notifyListeners();
    final stopwatch = Stopwatch()..start();

    try {
      final metadata = await _extractorRegistry.extract(cleanUrl);
      if (sequence != _requestSequence) return false;

      _metadata = metadata;
      _selectedQuality =
          QualityHelper.bestMatch(metadata.qualities, preferredQuality) ??
          metadata.bestQuality;
      _lastAnalysisDuration = stopwatch.elapsed;
      _lastAnalyzedAt = DateTime.now();
      _isAnalyzing = false;
      notifyListeners();
      return true;
    } catch (e) {
      if (sequence != _requestSequence) return false;
      _isAnalyzing = false;
      _errorMessage = _readableError(e, l10n.unableToAnalyze, l10n);
      if (e is ExtractionException) {
        _diagnosticCode =
            e.diagnosticCode ??
            '${UrlHelper.detectPlatform(cleanUrl).name}_extraction_failed';
        _attemptedStrategies = e.attemptedStrategies.isEmpty
            ? const ['extractor_registry']
            : e.attemptedStrategies;
      } else {
        _diagnosticCode =
            '${UrlHelper.detectPlatform(cleanUrl).name}_extraction_failed';
        _attemptedStrategies = const ['extractor_registry'];
      }
      _lastAnalysisDuration = stopwatch.elapsed;
      _lastAnalyzedAt = DateTime.now();
      notifyListeners();
      return false;
    }
  }

  Future<List<BatchAnalysisResult>> analyzeUrls(
    List<String> urls, {
    String preferredQuality = 'Highest',
    required AppLocalizations l10n,
  }) async {
    final cleanUrls = urls
        .map(UrlHelper.extractCleanUrl)
        .where(UrlHelper.isValidVideoUrl)
        .toSet()
        .take(maximumBatchUrls)
        .toList(growable: false);
    if (cleanUrls.isEmpty) {
      _isAnalyzing = false;
      _errorMessage = l10n.invalidVideoUrl;
      _batchResults = const [];
      notifyListeners();
      return const [];
    }
    if (cleanUrls.length == 1) {
      await analyzeUrl(
        cleanUrls.single,
        preferredQuality: preferredQuality,
        l10n: l10n,
      );
      return _metadata == null
          ? [BatchAnalysisResult(url: cleanUrls.single, error: _errorMessage)]
          : [BatchAnalysisResult(url: cleanUrls.single, metadata: _metadata)];
    }

    final sequence = ++_requestSequence;
    _isAnalyzing = true;
    _errorMessage = null;
    _metadata = null;
    _selectedQuality = null;
    _batchResults = const [];
    notifyListeners();

    final results = List<BatchAnalysisResult?>.filled(cleanUrls.length, null);
    var nextIndex = 0;

    Future<void> worker() async {
      while (nextIndex < cleanUrls.length) {
        final index = nextIndex++;
        final url = cleanUrls[index];
        final stopwatch = Stopwatch()..start();
        try {
          final metadata = await _extractorRegistry.extract(url);
          results[index] = BatchAnalysisResult(
            url: url,
            metadata: metadata,
            analysisDuration: stopwatch.elapsed,
          );
        } catch (error) {
          results[index] = BatchAnalysisResult(
            url: url,
            error: _readableError(error, l10n.unableToAnalyze, l10n),
            diagnosticCode: error is ExtractionException
                ? error.diagnosticCode ??
                      '${UrlHelper.detectPlatform(url).name}_extraction_failed'
                : '${UrlHelper.detectPlatform(url).name}_extraction_failed',
            analysisDuration: stopwatch.elapsed,
          );
        }
        if (sequence != _requestSequence) return;
        _batchResults = List.unmodifiable(
          results.whereType<BatchAnalysisResult>(),
        );
        notifyListeners();
      }
    }

    await Future.wait(
      List.generate(
        cleanUrls.length.clamp(0, maximumParallelAnalyses),
        (_) => worker(),
      ),
    );
    if (sequence != _requestSequence) return const [];
    _isAnalyzing = false;
    notifyListeners();
    return _batchResults;
  }

  Future<void> retryBatchResult(
    String url, {
    String preferredQuality = 'Highest',
    required AppLocalizations l10n,
  }) async {
    final index = _batchResults.indexWhere((result) => result.url == url);
    if (index == -1) return;
    _isAnalyzing = true;
    notifyListeners();
    final stopwatch = Stopwatch()..start();
    try {
      final metadata = await _extractorRegistry.extract(url);
      final updated = [..._batchResults];
      updated[index] = BatchAnalysisResult(
        url: url,
        metadata: metadata,
        selectedQuality:
            QualityHelper.bestMatch(metadata.qualities, preferredQuality) ??
            metadata.bestQuality,
        analysisDuration: stopwatch.elapsed,
      );
      _batchResults = List.unmodifiable(updated);
    } catch (error) {
      final updated = [..._batchResults];
      updated[index] = BatchAnalysisResult(
        url: url,
        error: _readableError(error, l10n.unableToAnalyze, l10n),
        diagnosticCode: error is ExtractionException
            ? error.diagnosticCode ??
                  '${UrlHelper.detectPlatform(url).name}_extraction_failed'
            : '${UrlHelper.detectPlatform(url).name}_extraction_failed',
        analysisDuration: stopwatch.elapsed,
      );
      _batchResults = List.unmodifiable(updated);
    } finally {
      _isAnalyzing = false;
      notifyListeners();
    }
  }

  void selectBatchQuality(String url, VideoQualityOption quality) {
    final result = _batchResults.where((entry) => entry.url == url).firstOrNull;
    if (result?.metadata == null ||
        !result!.metadata!.qualities.contains(quality)) {
      return;
    }
    result.selectedQuality = quality;
    notifyListeners();
  }

  void cancelBatchAnalysis() {
    if (!_isAnalyzing || _batchResults.isEmpty) return;
    _requestSequence++;
    _isAnalyzing = false;
    notifyListeners();
  }

  /// Strips the `Exception:` prefixes Dart adds so the user sees the message the
  /// extractor actually wrote.
  String _readableError(
    Object error,
    String fallbackErrorMessage,
    AppLocalizations l10n,
  ) {
    // Must come before the toString() fallback: an ExtractionException now
    // stringifies to its kind, which is not something to show a user.
    if (error is ExtractionException) {
      return describeExtractionFailure(error.failure, l10n);
    }
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
    _diagnosticCode = null;
    _attemptedStrategies = const [];
    _batchResults = const [];
    _lastAnalysisDuration = null;
    _lastAnalyzedAt = null;
    notifyListeners();
  }
}

class BatchAnalysisResult {
  BatchAnalysisResult({
    required this.url,
    this.metadata,
    this.error,
    this.diagnosticCode,
    this.analysisDuration,
    VideoQualityOption? selectedQuality,
  }) : selectedQuality = selectedQuality ?? metadata?.bestQuality;

  final String url;
  final VideoMetadata? metadata;
  final String? error;
  final String? diagnosticCode;
  final Duration? analysisDuration;
  VideoQualityOption? selectedQuality;
  bool get isSuccess => metadata != null;
}
