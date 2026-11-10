import 'base_extractor.dart';
import 'extraction_failure.dart';

/// The tracks a SoundCloud playlist lists. The public core reads no playlist;
/// the type is here because the app is written against it.
class SoundCloudSet {
  const SoundCloudSet({
    required this.title,
    required this.trackUrls,
    required this.trackCount,
  });

  final String title;

  /// Links to the tracks that were asked for.
  final List<String> trackUrls;

  /// How many tracks the playlist holds, which may be more than [trackUrls].
  final int trackCount;
}

/// Whether a link may stand for several tracks. Always false here, so the
/// app never takes a link for a playlist it could not read.
bool mayBeSoundCloudSet(String url) => false;

class SoundCloudSetReader {
  const SoundCloudSetReader();

  Future<SoundCloudSet> read(String url, {required int limit}) async {
    throw ExtractionException(
      const ExtractionFailure(ExtractionFailureKind.soundcloudSetUnavailable),
      diagnosticCode: 'public_core',
    );
  }
}
