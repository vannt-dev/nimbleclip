import 'dart:io';

import 'package:http/http.dart' as http;

import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../models/slideshow_source.dart';
import 'slideshow_failure.dart';

/// The local files a [SlideshowRenderer] needs, fetched from a
/// [SlideshowSource]'s remote URLs.
class SlideshowAssets {
  const SlideshowAssets({
    required this.imagePaths,
    required this.audioPath,
    required this.workingDir,
  });

  /// Local paths to the fetched images, in source order.
  final List<String> imagePaths;

  /// Local path to the fetched music track, or null when the post carried
  /// no music, or the track could not be fetched.
  final String? audioPath;

  /// The directory the assets were written into.
  final Directory workingDir;
}

/// Downloads a slideshow's images and (best-effort) music into [into],
/// returning the local paths the encoder will read.
///
/// Images are load-bearing: any failed image fetch throws
/// [SlideshowFailureKind.fetchFailed], since there is no slideshow without
/// its pictures. Music is not: a failed audio fetch is swallowed and leaves
/// [SlideshowAssets.audioPath] null, since a silent slideshow still renders
/// while a failed one does not.
Future<SlideshowAssets> fetchSlideshowAssets(
  SlideshowSource source, {
  required Directory into,
}) async {
  if (source.imageUrls.isEmpty) {
    throw const SlideshowException(SlideshowFailureKind.noImages);
  }

  final imagePaths = <String>[];
  for (var index = 0; index < source.imageUrls.length; index++) {
    final url = source.imageUrls[index];
    final extension = MediaFormatHelper.inferImageFormat(url);
    final path = '${into.path}/image_$index.$extension';

    http.Response response;
    try {
      response = await ExtractorHttp.getWithRetry(
        url,
        service: 'slideshow image',
      );
    } catch (error) {
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'image $index: $error',
      );
    }
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      throw SlideshowException(
        SlideshowFailureKind.fetchFailed,
        detail: 'image $index: HTTP ${response.statusCode}',
      );
    }
    await File(path).writeAsBytes(response.bodyBytes);
    imagePaths.add(path);
  }

  String? audioPath;
  final audioUrl = source.audioUrl;
  if (audioUrl != null) {
    try {
      final response = await ExtractorHttp.getWithRetry(
        audioUrl,
        service: 'slideshow audio',
      );
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final path = '${into.path}/audio.mp3';
        await File(path).writeAsBytes(response.bodyBytes);
        audioPath = path;
      }
    } catch (_) {
      // A silent slideshow beats no slideshow: swallow any audio failure.
    }
  }

  return SlideshowAssets(
    imagePaths: imagePaths,
    audioPath: audioPath,
    workingDir: into,
  );
}
