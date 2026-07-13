import 'package:flutter/material.dart';

/// Shows a modal dialog to rename a document. Pre-fills [currentName] (fully
/// selected) and returns the trimmed new name, or null on cancel OR when the
/// trimmed value is unchanged (so the caller does no pointless write). Shared by
/// the viewer and the library list (DRY). The name never leaves the device.
///
/// [suggest], when provided, is called once (on open) to fetch an optional
/// title suggestion (e.g. derived from OCR text). When it resolves to a
/// non-null, non-blank string, a tappable chip appears that fills the field
/// with the suggestion — the user still confirms or edits before Save, so the
/// suggestion is never applied silently. When [suggest] is null, or resolves
/// to null/blank, no chip renders and behavior is identical to omitting it.
Future<String?> showRenameDialog(
  BuildContext context,
  String currentName, {
  Future<String?> Function()? suggest,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName, suggest: suggest),
  );
}

class _RenameDialog extends StatefulWidget {
  final String currentName;
  final Future<String?> Function()? suggest;
  const _RenameDialog({required this.currentName, this.suggest});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  String? _suggestion;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.currentName.length,
      );
    final suggest = widget.suggest;
    if (suggest != null) {
      suggest().then((value) {
        if (!mounted) return;
        final trimmed = value?.trim();
        if (trimmed == null || trimmed.isEmpty) return;
        setState(() => _suggestion = trimmed);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applySuggestion() {
    final suggestion = _suggestion;
    if (suggestion == null) return;
    setState(() {
      _controller.text = suggestion;
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: suggestion.length,
      );
    });
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
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
          if (_suggestion != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: ActionChip(
                key: const Key('rename-suggestion'),
                avatar: const Icon(Icons.auto_awesome, size: 16),
                label: Text(_suggestion!),
                onPressed: _applySuggestion,
              ),
            ),
        ],
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
