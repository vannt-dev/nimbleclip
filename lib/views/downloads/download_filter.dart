import '../../core/utils/search_text.dart';
import '../../models/download_task.dart';
import '../../models/video_metadata.dart' show MediaKind;

/// The kinds of download the list can be narrowed to.
enum DownloadTypeFilter { all, video, audio, image }

/// What the downloads list is narrowed to: words typed into the search field
/// and one kind of media.
class DownloadFilter {
  final String query;
  final DownloadTypeFilter type;

  const DownloadFilter({this.query = '', this.type = DownloadTypeFilter.all});

  /// A title folded for search never changes, so it is worked out once per
  /// task and reused for every keystroke after that.
  static final Expando<String> _foldedTitles = Expando('foldedTitle');

  bool get isActive =>
      type != DownloadTypeFilter.all || query.trim().isNotEmpty;

  DownloadFilter copyWith({String? query, DownloadTypeFilter? type}) =>
      DownloadFilter(query: query ?? this.query, type: type ?? this.type);

  List<DownloadTask> apply(List<DownloadTask> tasks) {
    if (!isActive) return tasks;
    final words = foldForSearch(
      query,
    ).split(' ').where((word) => word.isNotEmpty).toList();
    return tasks
        .where((task) => _matchesType(task) && _matchesWords(task, words))
        .toList();
  }

  bool _matchesType(DownloadTask task) => switch (type) {
    DownloadTypeFilter.all => true,
    DownloadTypeFilter.video => task.kind == MediaKind.video,
    DownloadTypeFilter.audio => task.kind == MediaKind.audio,
    DownloadTypeFilter.image => task.kind == MediaKind.image,
  };

  static bool _matchesWords(DownloadTask task, List<String> words) {
    if (words.isEmpty) return true;
    final title = _foldedTitles[task] ??= foldForSearch(task.title);
    return words.every(title.contains);
  }
}
