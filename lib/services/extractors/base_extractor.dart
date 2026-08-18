import '../../models/video_metadata.dart';
import '../../models/video_platform.dart';

abstract class BaseVideoExtractor {
  VideoPlatform get platform;
  bool canHandle(String url);
  Future<VideoMetadata> extract(String url);
}
