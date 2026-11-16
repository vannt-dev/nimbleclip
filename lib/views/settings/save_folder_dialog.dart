import 'package:flutter/material.dart';

import '../../core/utils/save_folder_name.dart';
import '../../l10n/l10n.dart';
import '../../providers/settings_provider.dart';

/// Asks for the name of the folder saved files go into. An empty name
/// restores the default places; a refused name keeps the dialog open with the
/// reason under the field.
class SaveFolderDialog extends StatefulWidget {
  const SaveFolderDialog({super.key, required this.settings});

  final SettingsProvider settings;

  @override
  State<SaveFolderDialog> createState() => _SaveFolderDialogState();
}

class _SaveFolderDialogState extends State<SaveFolderDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.settings.saveFolderName ?? '',
  );
  SaveFolderProblem? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _problemText(BuildContext context) {
    final l10n = context.l10n;
    return switch (_problem) {
      null => null,
      SaveFolderProblem.invalidCharacters => l10n.saveFolderInvalidCharacters,
      SaveFolderProblem.startsWithDot => l10n.saveFolderStartsWithDot,
      SaveFolderProblem.tooLong => l10n.saveFolderTooLong(
        SaveFolderName.maxLength,
      ),
    };
  }

  Future<void> _save() async {
    final problem = await widget.settings.setSaveFolderName(_controller.text);
    if (!mounted) return;
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.saveFolder),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('saveFolderField'),
            controller: _controller,
            autofocus: true,
            maxLength: SaveFolderName.maxLength,
            decoration: InputDecoration(
              hintText: l10n.saveFolderHint,
              errorText: _problemText(context),
            ),
            onChanged: (value) =>
                setState(() => _problem = SaveFolderName.problemWith(value)),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 8),
          Text(l10n.saveFolderNote, style: const TextStyle(fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        ElevatedButton(
          onPressed: _problem == null ? _save : null,
          child: Text(l10n.saveFolderSave),
        ),
      ],
    );
  }
}
