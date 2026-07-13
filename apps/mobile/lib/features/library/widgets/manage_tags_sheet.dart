import 'package:flutter/material.dart';

import '../tag.dart';

/// Shows [ManageTagsSheet] as a modal bottom sheet and returns the final
/// selected tag id set, or null if dismissed without pressing Done (e.g.
/// swiped away).
Future<Set<int>?> showManageTagsSheet(
  BuildContext context, {
  required List<Tag> tags,
  required Set<int> initial,
  required Future<Tag> Function(String name) onCreateTag,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    builder: (_) => ManageTagsSheet(
      tags: tags,
      initial: initial,
      onCreateTag: onCreateTag,
      onDone: (selected) => Navigator.of(context).pop(selected),
    ),
  );
}

/// Per-document tag manager: a [Wrap] of [FilterChip]s seeded from [initial]
/// (the document's CURRENT tags — contrast [TagFilterSheet], which seeds from
/// an active filter), plus a "New tag…" affordance that creates a tag via
/// [onCreateTag] and adds + selects it in-place. "Done" reports the final
/// selection via [onDone]. Mirrors TagFilterSheet's chip-toggle structure.
class ManageTagsSheet extends StatefulWidget {
  final List<Tag> tags;
  final Set<int> initial;
  final Future<Tag> Function(String name) onCreateTag;
  final ValueChanged<Set<int>> onDone;

  const ManageTagsSheet({
    super.key,
    required this.tags,
    required this.initial,
    required this.onCreateTag,
    required this.onDone,
  });

  @override
  State<ManageTagsSheet> createState() => _ManageTagsSheetState();
}

class _ManageTagsSheetState extends State<ManageTagsSheet> {
  late final List<Tag> _tags = [...widget.tags];
  late final Set<int> _selected = {...widget.initial};

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _createTag() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _CreateTagDialog(),
    );
    if (name == null || !mounted) return;
    final tag = await widget.onCreateTag(name);
    if (!mounted) return;
    setState(() {
      _tags.add(tag);
      _selected.add(tag.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Tags', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _tags)
                  FilterChip(
                    key: Key('manage-tag-chip-${t.id}'),
                    label: Text(t.name),
                    selected: _selected.contains(t.id),
                    onSelected: (_) => _toggle(t.id),
                  ),
                ActionChip(
                  key: const Key('manage-tags-new'),
                  avatar: const Icon(Icons.add, size: 18),
                  label: const Text('New tag…'),
                  onPressed: _createTag,
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('manage-tags-done'),
              onPressed: () => widget.onDone(_selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small inline dialog to create a tag. Returns the trimmed tag name, or null
/// on cancel OR when the trimmed value is empty. Mirrors
/// [showCreateFolderDialog]'s structure (DRY pattern), namespaced under
/// `create-tag-*` keys so it coexists with the folder dialog in tests.
class _CreateTagDialog extends StatefulWidget {
  const _CreateTagDialog();

  @override
  State<_CreateTagDialog> createState() => _CreateTagDialogState();
}

class _CreateTagDialogState extends State<_CreateTagDialog> {
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
      key: const Key('create-tag-dialog'),
      title: const Text('New tag'),
      content: TextField(
        key: const Key('create-tag-field'),
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
          key: const Key('create-tag-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('create-tag-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
