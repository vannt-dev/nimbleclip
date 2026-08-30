import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/cors_helper.dart';
import '../../core/utils/local_video_source.dart';
import '../../l10n/l10n.dart';
import '../../models/video_metadata.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String? videoUrl;
  final String? localFilePath;
  final VoidCallback? onDownload;

  /// The other videos of the same post, swiped between. When it holds more
  /// than one, [videoUrl] is ignored in favour of [initialIndex] into this.
  ///
  /// Absent for a downloaded file, which has no set to belong to.
  final List<VideoQualityOption>? playlist;
  final int initialIndex;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    this.videoUrl,
    this.localFilePath,
    this.onDownload,
    this.playlist,
    this.initialIndex = 0,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  PageController? _pageController;
  late int _index;

  List<VideoQualityOption> get _playlist => widget.playlist ?? const [];
  bool get _isSwipeable => _playlist.length > 1;

  @override
  void initState() {
    super.initState();
    _index = _playlist.isEmpty
        ? 0
        : widget.initialIndex.clamp(0, _playlist.length - 1);
    if (_isSwipeable) _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (_isSwipeable)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '${_index + 1} / ${_playlist.length}',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          if (widget.onDownload != null)
            IconButton(
              icon: const Icon(
                Icons.download_rounded,
                color: AppColors.primaryLight,
              ),
              onPressed: widget.onDownload,
              tooltip: context.l10n.downloadThisVideo,
            ),
        ],
      ),
      body: SafeArea(child: _isSwipeable ? _pages() : _singleStage()),
    );
  }

  Widget _singleStage() => Center(
    child: VideoStage(
      videoUrl:
          widget.playlist?.elementAtOrNull(_index)?.downloadUrl ??
          widget.videoUrl,
      localFilePath: widget.localFilePath,
      isActive: true,
    ),
  );

  /// Only the page on screen plays. A neighbour that `PageView` has built ahead
  /// of the swipe would otherwise start its own audio out of sight.
  Widget _pages() => PageView.builder(
    controller: _pageController,
    itemCount: _playlist.length,
    onPageChanged: (index) => setState(() => _index = index),
    itemBuilder: (_, index) => Center(
      child: VideoStage(
        key: ValueKey(_playlist[index].id),
        videoUrl: _playlist[index].downloadUrl,
        isActive: index == _index,
      ),
    ),
  );
}

/// One video, loaded and played on its own.
///
/// Split out of the screen so several can sit in a page view without the
/// screen having to juggle their controllers: each stage owns exactly one, and
/// disposes it when the page view drops the page.
class VideoStage extends StatefulWidget {
  const VideoStage({
    super.key,
    this.videoUrl,
    this.localFilePath,
    required this.isActive,
  });

  final String? videoUrl;
  final String? localFilePath;

  /// Whether this is the page being looked at. A stage that is not active
  /// holds its position rather than playing.
  final bool isActive;

  @override
  State<VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends State<VideoStage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasInitialized = false;
  String? _errorMessage;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;
      unawaited(_initializePlayer());
    }
  }

  @override
  void didUpdateWidget(covariant VideoStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive == widget.isActive) return;
    final controller = _videoPlayerController;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(widget.isActive ? controller.play() : controller.pause());
  }

  Future<void> _initializePlayer() async {
    try {
      final localPath = widget.localFilePath;
      if (localPath != null && localPath.isNotEmpty) {
        if (!localPlaybackSupported(localPath)) {
          throw Exception(context.l10n.localFileMissing);
        }
        _videoPlayerController = createLocalVideoController(localPath);
      } else if (widget.videoUrl != null && widget.videoUrl!.isNotEmpty) {
        // Remote previews go through the CORS proxy on Web; the proxy forwards
        // Range headers so seeking still works.
        _videoPlayerController = VideoPlayerController.networkUrl(
          Uri.parse(CorsHelper.wrap(widget.videoUrl!)),
        );
      } else {
        throw Exception(context.l10n.noVideoSource);
      }

      await _videoPlayerController!.initialize();

      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: widget.isActive,
        looping: false,
        aspectRatio: _videoPlayerController!.value.aspectRatio > 0
            ? _videoPlayerController!.value.aspectRatio
            : 16 / 9,
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primaryLight,
          backgroundColor: Colors.grey.withAlpha(80),
          bufferedColor: Colors.white24,
        ),
        placeholder: Container(
          color: Colors.black,
          child: const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
        autoInitialize: true,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.videoPlaybackError(errorMessage),
                style: const TextStyle(color: Colors.white),
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_videoPlayerController?.dispose());
    _chewieController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const CircularProgressIndicator(color: AppColors.primary);
    }
    if (_errorMessage != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _isLoading = true;
                  _errorMessage = null;
                });
                unawaited(_initializePlayer());
              },
              child: Text(context.l10n.retry),
            ),
          ],
        ),
      );
    }
    return Chewie(controller: _chewieController!);
  }
}
