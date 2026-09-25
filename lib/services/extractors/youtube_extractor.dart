import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

import '../../core/utils/http_helper.dart';
import '../../core/utils/cors_helper.dart';
import '../../core/utils/json_scanner.dart';
import '../../core/utils/quality_helper.dart';
import '../../models/merge_source.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import '../slideshow/slideshow_renderer.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';

/// One adaptive stream as the planner needs it, free of the library's types
/// so the choice can be tested without a network manifest.
@visibleForTesting
class AdaptiveStream {
  const AdaptiveStream({
    required this.tag,
    required this.qualityLabel,
    required this.height,
    required this.container,
    required this.codecs,
    required this.url,
    required this.bytes,
    required this.bitrate,
  });

  final int tag;
  final String qualityLabel;
  final int height;
  final String container;
  final String codecs;
  final String url;
  final int bytes;
  final int bitrate;
}

class YouTubeExtractor extends BaseVideoExtractor {
  const YouTubeExtractor({
    this.useNativeClient = true,
    @visibleForTesting this.nativeHttpClient,
    this.canMergeStreams,
  });

  final bool useNativeClient;

  /// Transport for the native client; `null` uses the library's default.
  final http.Client? nativeHttpClient;

  /// Overrides the platform check behind [mergeStreams]; null asks the
  /// device.
  final bool? canMergeStreams;

  /// Whether to offer qualities above 360p, which only exist as separate
  /// picture and sound streams and must be joined on the device.
  ///
  /// Decided here rather than filtered in the UI: the default selection is
  /// made from the full list, so an option this device cannot produce would
  /// otherwise be picked as "Highest" and then hidden.
  bool get mergeStreams =>
      canMergeStreams ?? createSlideshowRenderer().isSupported;

  /// The highest quality offered as a merged download.
  static const int maxMergedHeight = 1080;

  /// The side YouTube names a quality after: a vertical Short labelled 720p
  /// is 720x1280, and comparing its height would call it 1280p.
  static int _shortSide(yt_lib.VideoResolution resolution) =>
      min(resolution.width, resolution.height);

  /// Picks one H.264 stream per quality above [aboveHeight], up to
  /// [maxMergedHeight], each paired with [audio].
  ///
  /// H.264 only: it is the one codec `MediaMuxer` puts in an MP4 on every
  /// supported Android version and every player opens. YouTube stops offering
  /// it above 1080p, which is where VP9 and AV1 take over.
  @visibleForTesting
  static List<VideoQualityOption> planMergedOptions({
    required List<AdaptiveStream> videos,
    required AdaptiveStream audio,
    required int aboveHeight,
  }) {
    final byLabel = <String, AdaptiveStream>{};
    for (final stream in videos) {
      if (stream.container != 'mp4' || !stream.codecs.startsWith('avc1')) {
        continue;
      }
      if (stream.height <= aboveHeight || stream.height > maxMergedHeight) {
        continue;
      }
      final current = byLabel[stream.qualityLabel];
      if (current == null || stream.bitrate > current.bitrate) {
        byLabel[stream.qualityLabel] = stream;
      }
    }
    final picked = byLabel.values.toList()
      ..sort((a, b) => b.height.compareTo(a.height));
    return [
      for (final stream in picked)
        VideoQualityOption.merged(
          id: 'yt_merged_${stream.tag}',
          label: VideoWithAudio(stream.qualityLabel),
          quality: stream.qualityLabel,
          sizeBytes: stream.bytes + audio.bytes,
          source: MergeSource(
            videoUrl: stream.url,
            audioUrl: audio.url,
            videoBytes: stream.bytes,
            audioBytes: audio.bytes,
          ),
        ),
    ];
  }

  @override
  VideoPlatform get platform => VideoPlatform.youtube;

  static final RegExp _playerJsUrl = RegExp(
    r'"(?:jsUrl|PLAYER_JS_URL)"\s*:\s*"([^"]+)"',
  );

  static final RegExp _videoIdPattern = RegExp(
    r'(?:youtu\.be/|youtube(?:-nocookie)?\.com/(?:embed/|v/|live/|shorts/|watch\?(?:.*&)?v=))([\w-]{11})',
  );

  @visibleForTesting
  static String? videoIdFrom(String url) =>
      _videoIdPattern.firstMatch(url)?.group(1);

  @override
  Future<VideoMetadata> extract(String url) async {
    final videoId = videoIdFrom(url);

    // Native platforms get the real deal: youtube_explode_dart deciphers
    // signature-protected stream URLs, which plain HTML scraping cannot.
    Object? nativeError;
    if (!kIsWeb && useNativeClient) {
      try {
        // Hand the library the parsed ID, not the URL: its Shorts pattern
        // requires the ID to end the string, so a copied share link such as
        // `/shorts/<id>?si=...` is rejected as an invalid URL.
        final native = await _extractNative(url, videoId ?? url);
        if (native != null) return native;
      } catch (e) {
        // Fall through to the watch-page strategy, but keep the error: the
        // fallback's own failure is what the user sees.
        nativeError = e;
      }
    }

    try {
      if (videoId == null) {
        throw ExtractionException(
          const ExtractionFailure(ExtractionFailureKind.youtubeInvalidId),
        );
      }
      return await _extractFromWatchPage(url, videoId);
    } on ExtractionException catch (e) {
      if (nativeError == null) rethrow;
      throw e.withSuppressedError('native-client: $nativeError');
    }
  }

  Future<VideoMetadata?> _extractNative(String url, String idOrUrl) async {
    final yt = yt_lib.YoutubeExplode(
      httpClient: nativeHttpClient == null
          ? null
          : yt_lib.YoutubeHttpClient(nativeHttpClient),
    );
    try {
      final video = await yt.videos.get(idOrUrl);
      final manifest = await yt.videos.streamsClient.getManifest(video.id);
      final qualities = <VideoQualityOption>[];

      for (final stream in manifest.muxed.sortByVideoQuality()) {
        qualities.add(
          VideoQualityOption(
            id: 'yt_muxed_${stream.tag}',
            label: VideoWithAudio(stream.qualityLabel),
            quality: stream.qualityLabel,
            format: stream.container.name,
            downloadUrl: stream.url.toString(),
            sizeBytes: stream.size.totalBytes,
          ),
        );
      }

      // AAC in MP4 only. The highest bitrate overall is usually Opus in WebM,
      // which was once offered here and saved under an .m4a name it is not.
      final aacStreams = manifest.audioOnly
          .where((stream) => stream.container == yt_lib.StreamContainer.mp4)
          .toList();
      final bestAudio = aacStreams.isEmpty
          ? null
          : aacStreams.withHighestBitrate();

      if (bestAudio != null && mergeStreams) {
        final maxMuxedHeight = manifest.muxed.fold<int>(
          0,
          (height, stream) => max(height, _shortSide(stream.videoResolution)),
        );
        qualities.addAll(
          planMergedOptions(
            videos: [
              for (final stream in manifest.videoOnly)
                AdaptiveStream(
                  tag: stream.tag,
                  qualityLabel: stream.qualityLabel,
                  height: _shortSide(stream.videoResolution),
                  container: stream.container.name,
                  codecs: stream.codec.parameters['codecs'] ?? '',
                  url: stream.url.toString(),
                  bytes: stream.size.totalBytes,
                  bitrate: stream.bitrate.bitsPerSecond,
                ),
            ],
            audio: AdaptiveStream(
              tag: bestAudio.tag,
              qualityLabel: '',
              height: 0,
              container: bestAudio.container.name,
              codecs: bestAudio.codec.parameters['codecs'] ?? '',
              url: bestAudio.url.toString(),
              bytes: bestAudio.size.totalBytes,
              bitrate: bestAudio.bitrate.bitsPerSecond,
            ),
            aboveHeight: maxMuxedHeight,
          ),
        );
      }

      if (bestAudio != null) {
        final kbps = bestAudio.bitrate.kiloBitsPerSecond.round();
        qualities.add(
          VideoQualityOption(
            id: 'yt_audio_${bestAudio.tag}',
            label: AudioM4a(kbps),
            quality: 'Audio ($kbps kbps)',
            format: 'm4a',
            downloadUrl: bestAudio.url.toString(),
            sizeBytes: bestAudio.size.totalBytes,
            kind: MediaKind.audio,
          ),
        );
      }

      if (qualities.isEmpty) return null;

      return VideoMetadata(
        id: video.id.value,
        originalUrl: url,
        title: video.title,
        description: video.description,
        author: video.author,
        coverUrl: video.thumbnails.highResUrl.isNotEmpty
            ? video.thumbnails.highResUrl
            : video.thumbnails.mediumResUrl,
        duration: video.duration,
        platform: VideoPlatform.youtube,
        qualities: QualityHelper.sortedByQuality(qualities),
        viewCount: video.engagement.viewCount,
        likeCount: video.engagement.likeCount,
      );
    } finally {
      yt.close();
    }
  }

  Future<VideoMetadata> _extractFromWatchPage(
    String url,
    String videoId,
  ) async {
    final http.Response response;
    try {
      response = await ExtractorHttp.get(
        'https://www.youtube.com/watch?v=$videoId',
      );
    } catch (e) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.youtubeLoadFailed,
          detail: e.toString(),
        ),
      );
    }

    // A balanced-brace scan, not a non-greedy regex: the player response
    // contains nested objects and strings that truncate `({.+?});` early.
    final blob = extractJsonAfterMarker(
      response.body,
      'ytInitialPlayerResponse',
    );
    if (blob == null) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.youtubeNoPlayerData),
      );
    }

    final Map<String, dynamic> json;
    try {
      json = jsonDecode(blob) as Map<String, dynamic>;
    } catch (e) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.youtubeInvalidData,
          detail: e.toString(),
        ),
      );
    }

    final playability = json['playabilityStatus'] as Map<String, dynamic>?;
    final status = playability?['status']?.toString();
    if (status != null && status != 'OK') {
      final reason = playability?['reason']?.toString() ?? status;
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.youtubePlaybackRejected,
          detail: reason,
        ),
      );
    }

    final details = json['videoDetails'] as Map<String, dynamic>? ?? {};
    final streamingData = json['streamingData'] as Map<String, dynamic>?;
    final qualities = <VideoQualityOption>[];
    var hasCipheredStreams = false;
    final allFormats = <Map<String, dynamic>>[
      for (final entry in streamingData?['formats'] as List<dynamic>? ?? [])
        entry as Map<String, dynamic>,
      for (final entry
          in streamingData?['adaptiveFormats'] as List<dynamic>? ?? [])
        entry as Map<String, dynamic>,
    ];
    final deciphered = kIsWeb
        ? await _decipherWebStreams(response.body, allFormats)
        : const <String, String>{};

    /// `signatureCipher` streams need YouTube's player JS to be deciphered,
    /// which only the native path can do — note them so the error message can
    /// say why nothing was found.
    String? usableUrl(Map<String, dynamic> format) {
      final directUrl = format['url']?.toString();
      if (directUrl != null && directUrl.isNotEmpty) return directUrl;
      final cipher = format['signatureCipher']?.toString();
      if (cipher != null) {
        hasCipheredStreams = true;
        return deciphered[cipher];
      }
      return null;
    }

    final muxed = streamingData?['formats'] as List<dynamic>? ?? [];
    for (var i = 0; i < muxed.length; i++) {
      final format = muxed[i] as Map<String, dynamic>;
      final directUrl = usableUrl(format);
      if (directUrl == null) continue;

      final mimeType = format['mimeType']?.toString() ?? 'video/mp4';
      final quality =
          format['qualityLabel']?.toString() ?? '${format['height'] ?? ''}p';
      qualities.add(
        VideoQualityOption(
          id: 'yt_video_${videoId}_$i',
          label: VideoWithAudio(quality),
          quality: quality,
          format: mimeType.contains('webm') ? 'webm' : 'mp4',
          downloadUrl: directUrl,
          sizeBytes: int.tryParse(format['contentLength']?.toString() ?? ''),
        ),
      );
    }

    // The adaptive list carries a dozen audio renditions; only the highest
    // bitrate one is worth offering.
    Map<String, dynamic>? bestAudio;
    for (final entry
        in streamingData?['adaptiveFormats'] as List<dynamic>? ?? []) {
      final format = entry as Map<String, dynamic>;
      if (!(format['mimeType']?.toString() ?? '').startsWith('audio/')) {
        continue;
      }
      if (usableUrl(format) == null) {
        continue;
      }
      final bitrate = (format['bitrate'] as num?) ?? 0;
      final bestBitrate = (bestAudio?['bitrate'] as num?) ?? -1;
      if (bitrate > bestBitrate) {
        bestAudio = format;
      }
    }

    if (bestAudio != null) {
      final kbps = (((bestAudio['bitrate'] as num?) ?? 128000) / 1000).round();
      qualities.add(
        VideoQualityOption(
          id: 'yt_audio_$videoId',
          label: AudioM4a(kbps),
          quality: 'Audio ($kbps kbps)',
          format: 'm4a',
          downloadUrl: bestAudio['url'].toString(),
          sizeBytes: int.tryParse(bestAudio['contentLength']?.toString() ?? ''),
          kind: MediaKind.audio,
        ),
      );
    }

    if (qualities.isEmpty) {
      throw ExtractionException(
        hasCipheredStreams
            ? const ExtractionFailure(
                ExtractionFailureKind.youtubeCipherUnsupported,
              )
            : const ExtractionFailure(ExtractionFailureKind.youtubeNoStreams),
        diagnosticCode: hasCipheredStreams
            ? 'youtube_signature_decipher_failed'
            : 'youtube_no_streams',
        attemptedStrategies: const [
          'native-client',
          'watch-page',
          'web-decipher',
        ],
      );
    }

    return VideoMetadata(
      id: videoId,
      originalUrl: url,
      title: details['title']?.toString() ?? 'YouTube Video',
      description: details['shortDescription']?.toString(),
      author: details['author']?.toString() ?? 'YouTube Creator',
      coverUrl: 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg',
      duration: _durationFrom(details['lengthSeconds']),
      platform: VideoPlatform.youtube,
      qualities: QualityHelper.sortedByQuality(qualities),
      viewCount: int.tryParse(details['viewCount']?.toString() ?? ''),
    );
  }

  Future<Map<String, String>> _decipherWebStreams(
    String watchPage,
    List<Map<String, dynamic>> formats,
  ) async {
    final ciphers = formats
        .map((format) => format['signatureCipher']?.toString())
        .whereType<String>()
        .toSet()
        .toList(growable: false);
    if (ciphers.isEmpty) return const {};

    final playerMatch = _playerJsUrl.firstMatch(watchPage);
    if (playerMatch == null) return const {};
    try {
      final relative = jsonDecode('"${playerMatch.group(1)!}"') as String;
      final playerUrl = Uri.parse(
        relative.startsWith('http')
            ? relative
            : 'https://www.youtube.com$relative',
      ).toString();
      final response = await http
          .post(
            Uri.parse(CorsHelper.youtubeDecipherPath),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'playerUrl': playerUrl, 'ciphers': ciphers}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return const {};
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final urls = (payload['urls'] as List<dynamic>? ?? [])
          .map((value) => value.toString())
          .toList(growable: false);
      if (urls.length != ciphers.length) return const {};
      return {
        for (var index = 0; index < ciphers.length; index++)
          ciphers[index]: urls[index],
      };
    } catch (_) {
      return const {};
    }
  }

  Duration? _durationFrom(Object? lengthSeconds) {
    final seconds = int.tryParse(lengthSeconds?.toString() ?? '');
    return seconds != null && seconds > 0 ? Duration(seconds: seconds) : null;
  }
}
