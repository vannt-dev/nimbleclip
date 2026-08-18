import 'package:flutter/material.dart';
import '../core/utils/url_helper.dart';
import '../models/video_metadata.dart';
import '../services/extractors/registry.dart';

class VideoExtractorProvider extends ChangeNotifier {
  VideoMetadata? _metadata;
  VideoQualityOption? _selectedQuality;
  bool _isAnalyzing = false;
  String? _errorMessage;
  String _currentUrl = '';

  VideoMetadata? get metadata => _metadata;
  VideoQualityOption? get selectedQuality => _selectedQuality;
  bool get isAnalyzing => _isAnalyzing;
  String? get errorMessage => _errorMessage;
  String get currentUrl => _currentUrl;
  bool get hasResult => _metadata != null;

  VideoQualityOption? _findBestMatchingQuality(
      List<VideoQualityOption> options, String preferred) {
    if (options.isEmpty) return null;

    if (preferred == 'Audio') {
      final audio = options.firstWhere(
        (o) => o.isAudioOnly,
        orElse: () => options.first,
      );
      return audio;
    }

    final videoOnly = options.where((o) => !o.isAudioOnly).toList();
    if (videoOnly.isEmpty) return options.first;

    if (preferred == '720p') {
      return videoOnly.firstWhere(
        (o) => o.quality.contains('720'),
        orElse: () => videoOnly.first,
      );
    } else if (preferred == '480p') {
      return videoOnly.firstWhere(
        (o) => o.quality.contains('480'),
        orElse: () => videoOnly.first,
      );
    } else if (preferred == '360p') {
      return videoOnly.lastWhere(
        (o) => o.quality.contains('360') || o.quality.contains('SD'),
        orElse: () => videoOnly.last,
      );
    }

    // Default 'Highest'
    return videoOnly.first;
  }

  Future<bool> analyzeUrl(String url, {String preferredQuality = 'Highest'}) async {
    final cleanUrl = UrlHelper.extractCleanUrl(url);
    if (cleanUrl.isEmpty || !UrlHelper.isValidVideoUrl(cleanUrl)) {
      _errorMessage = 'Vui lòng nhập đường dẫn video hợp lệ (http/https).';
      notifyListeners();
      return false;
    }

    _isAnalyzing = true;
    _errorMessage = null;
    _metadata = null;
    _selectedQuality = null;
    _currentUrl = cleanUrl;
    notifyListeners();

    try {
      final meta = await ExtractorRegistry.extract(cleanUrl);
      _metadata = meta;
      if (meta.qualities.isNotEmpty) {
        _selectedQuality =
            _findBestMatchingQuality(meta.qualities, preferredQuality) ??
                meta.bestQuality ??
                meta.qualities.first;
      }
      _isAnalyzing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _isAnalyzing = false;
      _errorMessage = e.toString().replaceAll('Exception:', '').trim();
      notifyListeners();
      return false;
    }
  }

  void selectQuality(VideoQualityOption quality) {
    _selectedQuality = quality;
    notifyListeners();
  }

  void clear() {
    _metadata = null;
    _selectedQuality = null;
    _isAnalyzing = false;
    _errorMessage = null;
    _currentUrl = '';
    notifyListeners();
  }
}
