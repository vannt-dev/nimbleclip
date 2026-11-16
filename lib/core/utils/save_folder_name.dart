/// Why a folder name for saved files was refused.
enum SaveFolderProblem { invalidCharacters, startsWithDot, tooLong }

/// The name of the folder saved files go into, inside the gallery's Pictures
/// and Movies folders and the Music library. No name means the default
/// places: Pictures, Movies and Music/NimbleClip.
///
/// One folder level only: the name may not hold a path separator, so files
/// always stay where the gallery and music apps look for them.
class SaveFolderName {
  SaveFolderName._();

  static const int maxLength = 40;

  static final RegExp _invalid = RegExp(r'[/\\:*?"<>|\x00-\x1F\x7F]');

  /// Null when [input] can be used (an empty name included).
  static SaveFolderProblem? problemWith(String input) {
    final name = input.trim();
    if (name.isEmpty) return null;
    if (_invalid.hasMatch(name)) return SaveFolderProblem.invalidCharacters;
    if (name.startsWith('.')) return SaveFolderProblem.startsWithDot;
    if (name.length > maxLength) return SaveFolderProblem.tooLong;
    return null;
  }

  /// The trimmed name, or null for the default folders. Only for a name
  /// [problemWith] accepts.
  static String? normalize(String input) {
    final name = input.trim();
    return name.isEmpty ? null : name;
  }
}
