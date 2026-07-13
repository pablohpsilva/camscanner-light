import 'package:flutter/material.dart';

import '../tag.dart';

/// Shows [TagFilterSheet] as a modal bottom sheet and returns the selected tag
/// id set, or null if dismissed without pressing Done (e.g. swiped away).
Future<Set<int>?> showTagFilterSheet(
  BuildContext context, {
  required List<Tag> tags,
  required Set<int> initial,
}) {
  return showModalBottomSheet<Set<int>>(
    context: context,
    builder: (_) => TagFilterSheet(
      tags: tags,
      initial: initial,
      onDone: (selected) => Navigator.of(context).pop(selected),
    ),
  );
}

/// Multi-select tag filter (AND semantics applied by the caller): a [Wrap] of
/// [FilterChip]s seeded from [initial], plus a "Done" button that reports the
/// final selection via [onDone]. Stateful so chip taps update in place without
/// the caller re-building the whole sheet.
class TagFilterSheet extends StatefulWidget {
  final List<Tag> tags;
  final Set<int> initial;
  final ValueChanged<Set<int>> onDone;

  const TagFilterSheet({
    super.key,
    required this.tags,
    required this.initial,
    required this.onDone,
  });

  @override
  State<TagFilterSheet> createState() => _TagFilterSheetState();
}

class _TagFilterSheetState extends State<TagFilterSheet> {
  late final Set<int> _selected = {...widget.initial};

  void _toggle(int id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
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
            Text(
              'Filter by tag',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in widget.tags)
                  FilterChip(
                    key: Key('tag-filter-chip-${t.id}'),
                    label: Text(t.name),
                    selected: _selected.contains(t.id),
                    onSelected: (_) => _toggle(t.id),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('tag-filter-done'),
              onPressed: () => widget.onDone(_selected),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
