import 'package:flutter/material.dart';

/// Shows a modal dialog to create a folder. Returns the trimmed folder name,
/// or null on cancel OR when the trimmed value is empty (so the caller does no
/// pointless write). Mirrors [showRenameDialog]'s structure (DRY pattern).
Future<String?> showCreateFolderDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _CreateFolderDialog(),
  );
}

class _CreateFolderDialog extends StatefulWidget {
  const _CreateFolderDialog();

  @override
  State<_CreateFolderDialog> createState() => _CreateFolderDialogState();
}

class _CreateFolderDialogState extends State<_CreateFolderDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  void _save() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('create-folder-dialog'),
      title: const Text('New folder'),
      content: TextField(
        key: const Key('create-folder-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_canSave) _save();
        },
      ),
      actions: [
        TextButton(
          key: const Key('create-folder-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('create-folder-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
