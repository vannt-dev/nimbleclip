import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_colors.dart';
import '../../core/utils/cors_helper.dart';
import '../../core/utils/local_video_source.dart';
import '../../l10n/l10n.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String title;
  final String? videoUrl;
  final String? localFilePath;
  final VoidCallback? onDownload;

  const VideoPlayerScreen({
    super.key,
    required this.title,
    this.videoUrl,
    this.localFilePath,
    this.onDownload,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isLoading = true;
  bool _hasInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitialized) {
      _hasInitialized = true;
      unawaited(_initializePlayer());
    }
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
        autoPlay: true,
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
      body: SafeArea(
        child: Center(
          child: _isLoading
              ? const CircularProgressIndicator(color: AppColors.primary)
              : _errorMessage != null
              ? Padding(
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
                )
              : Chewie(controller: _chewieController!),
        ),
      ),
    );
  }
}
