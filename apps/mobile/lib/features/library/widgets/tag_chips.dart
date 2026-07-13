import 'package:flutter/material.dart';

import '../tag.dart';

/// Read-only display of a document's tags: a [Wrap] of small [Chip]s, one per
/// tag. Renders nothing (a zero-size [SizedBox]) when [tags] is empty, so
/// callers can embed this unconditionally in a card without changing that
/// card's layout for tag-less documents (existing card tests stay
/// byte-identical).
class TagChips extends StatelessWidget {
  final List<Tag> tags;

  const TagChips({super.key, required this.tags});

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final t in tags)
          Chip(
            key: Key('tag-chip-${t.id}'),
            label: Text(t.name),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: const TextStyle(fontSize: 11),
          ),
      ],
    );
  }
}
