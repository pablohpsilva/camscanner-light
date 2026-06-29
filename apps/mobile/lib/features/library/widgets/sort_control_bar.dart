import 'package:flutter/material.dart';

import '../document_sort.dart';

/// Inline segmented sort control shown under the HomeScreen AppBar (only when
/// the library is non-empty). Three ChoiceChips — Name, Created, Modified. The
/// active chip is selected and shows a direction arrow; tapping any chip asks
/// the parent for the next sort. State lives in the parent (HomeScreen); this
/// widget is pure presentation.
class SortControlBar extends StatelessWidget {
  final DocumentSort sort;
  final ValueChanged<SortCriterion> onCriterionTapped;
  const SortControlBar({
    super.key,
    required this.sort,
    required this.onCriterionTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('sort-control-bar'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // Wrap (not Row): three chips + the active chip's direction arrow can
      // exceed a narrow phone's width and overflow a Row. Wrap flows to a
      // second line instead. (Host tests at 800x600 would not catch a Row
      // overflow; only the device lane would.)
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _chip('sort-chip-name', 'Name', SortCriterion.name),
          _chip('sort-chip-created', 'Created', SortCriterion.created),
          _chip('sort-chip-modified', 'Modified', SortCriterion.modified),
        ],
      ),
    );
  }

  Widget _chip(String key, String label, SortCriterion criterion) {
    final active = sort.criterion == criterion;
    return ChoiceChip(
      key: Key(key),
      selected: active,
      onSelected: (_) => onCriterionTapped(criterion),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (active) ...[
            const SizedBox(width: 4),
            Icon(
              sort.direction == SortDirection.asc
                  ? Icons.arrow_upward
                  : Icons.arrow_downward,
              key: Key(sort.direction == SortDirection.asc
                  ? 'sort-direction-asc'
                  : 'sort-direction-desc'),
              // Screen readers announce the chip label + this, e.g. "Name,
              // ascending" — the arrow is otherwise unlabeled.
              semanticLabel:
                  sort.direction == SortDirection.asc ? 'ascending' : 'descending',
              size: 16,
            ),
          ],
        ],
      ),
    );
  }
}
