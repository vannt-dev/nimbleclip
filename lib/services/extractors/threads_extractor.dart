import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/utils/http_helper.dart';
import '../../core/utils/media_format_helper.dart';
import '../../core/utils/quality_helper.dart';
import '../../core/utils/text_unescape.dart';
import '../../models/quality_descriptor.dart';
import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';
import 'base_extractor.dart';
import 'extraction_failure.dart';
import 'parse_offloading.dart';

/// One picture or video of a Threads post, as found in the page.
class ThreadsMedia {
  const ThreadsMedia({
    required this.url,
    required this.isVideo,
    this.thumbnail,
  });

  final String url;
  final bool isVideo;

  /// A still of the video. Null for a picture, which is its own thumbnail.
  final String? thumbnail;
}

/// What the page says about a post. Plain data, so it can cross an isolate.
class ThreadsPost {
  const ThreadsPost({
    required this.media,
    this.author,
    this.caption,
    this.likeCount,
  });

  final List<ThreadsMedia> media;
  final String? author;
  final String? caption;
  final int? likeCount;
}

/// Threads posts: pictures, videos, and carousels mixing the two.
///
/// A post page carries its media as inline JSON, in the same shape Instagram
/// uses (`image_versions2`, `video_versions`, `carousel_media`). Threads only
/// puts that JSON in the page for search crawlers: a browser receives an empty
/// shell that fetches the post later through an API that needs a login. The
/// request therefore goes out with [AppConstants.searchCrawlerUserAgent].
class ThreadsExtractor extends BaseVideoExtractor {
  const ThreadsExtractor();

  @override
  VideoPlatform get platform => VideoPlatform.threads;

  /// `/@account/post/<code>` is what the Share action produces; `/t/<code>` is
  /// the older short form.
  static final RegExp _postCode = RegExp(r'/(?:post|t)/([A-Za-z0-9_-]+)');
  static final RegExp _jsonScripts = RegExp(
    r'''<script[^>]*type=["']application/json["'][^>]*>([\s\S]*?)</script>''',
  );

  /// The post's code, or null when [url] is not a post link.
  static String? postCodeOf(String url) {
    final path = Uri.tryParse(url.trim())?.path ?? '';
    return _postCode.firstMatch(path)?.group(1);
  }

  @override
  Future<VideoMetadata> extract(String url) async {
    final code = postCodeOf(url);
    if (code == null) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.threadsInvalidPost),
      );
    }

    // Always the current domain: threads.net answers with a redirect, and the
    // page behind a redirect comes back without the post. Tracking parameters
    // are not needed to load it either.
    final requestedPath = Uri.parse(url.trim()).path;
    var html = await _fetchPage(requestedPath);
    var post = await _parse(html, code);

    // The short form (/t/<code>) is such a redirect. The page it lands on
    // still names the post's own address, so ask for that one.
    if (post == null) {
      final ownPath = _ownPath(html, code);
      if (ownPath != null && ownPath != requestedPath) {
        html = await _fetchPage(ownPath);
        post = await _parse(html, code);
      }
    }

    if (post == null || post.media.isEmpty) {
      throw ExtractionException(
        const ExtractionFailure(ExtractionFailureKind.threadsNoMedia),
        suppressedError: post == null
            ? 'post page: no data for $code'
            : 'post page: the post has no picture or video',
      );
    }

    return _build(code, url, post);
  }

  Future<String> _fetchPage(String path) async {
    try {
      final response = await ExtractorHttp.get(
        Uri(scheme: 'https', host: 'www.threads.com', path: path).toString(),
        userAgent: AppConstants.searchCrawlerUserAgent,
      );
      if (response.statusCode >= 400) {
        throw ExtractionException(
          const ExtractionFailure(ExtractionFailureKind.threadsNoMedia),
          suppressedError: 'post page: HTTP ${response.statusCode}',
        );
      }
      return response.body;
    } on ExtractionException {
      rethrow;
    } catch (error) {
      throw ExtractionException(
        ExtractionFailure(
          ExtractionFailureKind.linkAccessFailed,
          detail: '$error',
        ),
      );
    }
  }

  // The code travels in front of the page: a parser handed to an isolate
  // takes exactly one argument.
  Future<ThreadsPost?> _parse(String html, String code) => parseOffMainIsolate(
    _parseTagged,
    '$code\n$html',
    debugLabel: 'threads post',
  );

  /// The `/@account/post/<code>` path a page gives for [code], if it has one.
  static String? _ownPath(String html, String code) {
    final match = RegExp(
      r'threads\.(?:com|net)/(?:@|&#064;|%40)([A-Za-z0-9._]+)/post/'
      '${RegExp.escape(code)}',
    ).firstMatch(html);
    return match == null ? null : '/@${match.group(1)}/post/$code';
  }

  static ThreadsPost? _parseTagged(String tagged) {
    final split = tagged.indexOf('\n');
    return parsePost(tagged.substring(split + 1), tagged.substring(0, split));
  }

  /// Finds the post with [code] in a page and lists its media.
  ///
  /// A page holds many posts - the one asked for, then replies and
  /// suggestions - so only the object carrying this code counts. Static and
  /// free of instance state so it can run on a background isolate.
  static ThreadsPost? parsePost(String html, String code) {
    Map<String, dynamic>? found;

    void visit(dynamic value) {
      if (found != null) return;
      if (value is Map<String, dynamic>) {
        if (value['code'] == code && value.containsKey('media_type')) {
          found = value;
          return;
        }
        value.values.forEach(visit);
      } else if (value is List) {
        value.forEach(visit);
      }
    }

    for (final script in _jsonScripts.allMatches(html)) {
      final body = script.group(1) ?? '';
      // Most blocks describe the page, not a post; skip them unparsed.
      if (!body.contains(code)) continue;
      try {
        visit(jsonDecode(decodeHtmlEntities(body)));
      } catch (_) {
        // One unreadable block must not hide the post in another.
      }
      if (found != null) break;
    }

    final post = found;
    if (post == null) return null;

    // A post that only quotes or reposts another shows that one's media, and a
    // post can also carry a video "inline" from Instagram. What the post holds
    // itself comes first.
    var media = _mediaIn(post);
    final info = post['text_post_app_info'];
    if (media.isEmpty && info is Map<String, dynamic>) {
      final share = info['share_info'];
      final shared = share is Map<String, dynamic>
          ? [share['quoted_post'], share['reposted_post']]
          : const <dynamic>[];
      for (final other in [...shared, info['linked_inline_media']]) {
        if (other is! Map<String, dynamic>) continue;
        media = _mediaIn(other);
        if (media.isNotEmpty) break;
      }
    }

    final user = post['user'];
    final caption = post['caption'];
    final likes = post['like_count'];
    return ThreadsPost(
      media: media,
      author: user is Map<String, dynamic> ? user['username'] as String? : null,
      caption: caption is Map<String, dynamic>
          ? caption['text'] as String?
          : null,
      likeCount: likes is int ? likes : null,
    );
  }

  /// Every picture and video [post] holds itself, a carousel's in order.
  static List<ThreadsMedia> _mediaIn(Map<String, dynamic> post) {
    final carousel = post['carousel_media'];
    final items = carousel is List && carousel.isNotEmpty
        ? carousel.whereType<Map<String, dynamic>>()
        : [post];
    return [for (final item in items) ?_mediaOf(item)];
  }

  /// The video of [item] when it has one, else its largest picture.
  static ThreadsMedia? _mediaOf(Map<String, dynamic> item) {
    final picture = _largestPicture(item['image_versions2']);

    final versions = item['video_versions'];
    if (versions is List) {
      for (final version in versions) {
        final url = version is Map<String, dynamic> ? version['url'] : null;
        if (url is String && url.isNotEmpty) {
          return ThreadsMedia(url: url, isVideo: true, thumbnail: picture);
        }
      }
    }

    return picture == null ? null : ThreadsMedia(url: picture, isVideo: false);
  }

  static String? _largestPicture(dynamic versions) {
    final candidates = versions is Map<String, dynamic>
        ? versions['candidates']
        : null;
    if (candidates is! List) return null;

    String? best;
    var bestWidth = -1;
    for (final candidate in candidates) {
      if (candidate is! Map<String, dynamic>) continue;
      final url = candidate['url'];
      final width = candidate['width'];
      if (url is! String || url.isEmpty) continue;
      final size = width is int ? width : 0;
      if (size > bestWidth) {
        best = url;
        bestWidth = size;
      }
    }
    return best;
  }

  VideoMetadata _build(String code, String originalUrl, ThreadsPost post) {
    final caption = post.caption?.trim();
    final hasCaption = caption != null && caption.isNotEmpty;
    final videos = post.media.where((item) => item.isVideo).toList();
    final pictures = post.media.where((item) => !item.isVideo).toList();

    return VideoMetadata(
      id: code,
      originalUrl: originalUrl,
      title: hasCaption ? caption : 'Threads post ($code)',
      description: hasCaption ? caption : null,
      author: post.author ?? 'Threads',
      coverUrl: post.media.first.thumbnail ?? post.media.first.url,
      platform: VideoPlatform.threads,
      likeCount: post.likeCount,
      qualities: QualityHelper.sortedByQuality([
        for (var index = 0; index < videos.length; index++)
          VideoQualityOption(
            id: 'threads_video_${index + 1}_$code',
            mediaId: 'threads_video_${index + 1}_$code',
            // A lone video has nothing to be told apart from.
            label: videos.length == 1
                ? const OriginalMp4()
                : VideoIndex(index + 1),
            quality: 'Original',
            format: 'mp4',
            downloadUrl: videos[index].url,
            thumbnailUrl: videos[index].thumbnail,
          ),
        for (var index = 0; index < pictures.length; index++)
          VideoQualityOption.image(
            id: 'threads_image_${index + 1}_$code',
            mediaId: 'threads_image_${index + 1}_$code',
            label: ImageIndex(index + 1),
            format: MediaFormatHelper.inferImageFormat(pictures[index].url),
            downloadUrl: pictures[index].url,
            thumbnailUrl: pictures[index].url,
          ),
      ]),
    );
  }
}
