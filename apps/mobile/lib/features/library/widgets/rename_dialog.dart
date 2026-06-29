import 'package:flutter/material.dart';

/// Shows a modal dialog to rename a document. Pre-fills [currentName] (fully
/// selected) and returns the trimmed new name, or null on cancel OR when the
/// trimmed value is unchanged (so the caller does no pointless write). Shared by
/// the viewer and the library list (DRY). The name never leaves the device.
Future<String?> showRenameDialog(BuildContext context, String currentName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName),
  );
}

class _RenameDialog extends StatefulWidget {
  final String currentName;
  const _RenameDialog({required this.currentName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName)
      ..selection = TextSelection(
          baseOffset: 0, extentOffset: widget.currentName.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  void _save() {
    final trimmed = _controller.text.trim();
    // Unchanged -> null so the caller skips the write (no pointless modifiedAt bump).
    Navigator.of(context).pop(trimmed == widget.currentName ? null : trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('rename-dialog'),
      title: const Text('Rename document'),
      content: TextField(
        key: const Key('rename-field'),
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
          key: const Key('rename-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('rename-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
