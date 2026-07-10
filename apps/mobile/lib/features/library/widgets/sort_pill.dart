import 'package:flutter/material.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/theme/ream_colors.dart';

/// A compact pill that shows the active [DocumentSort] criterion and a
/// direction arrow, and opens a popup menu to pick a different criterion.
///
/// This widget is purely presentational: it calls [onCriterionSelected] with
/// the chosen [SortCriterion] and leaves state management to the parent.
class SortPill extends StatelessWidget {
  const SortPill({
    required this.sort,
    required this.onCriterionSelected,
    super.key,
  });

  final DocumentSort sort;
  final ValueChanged<SortCriterion> onCriterionSelected;

  String get _criterionLabel {
    switch (sort.criterion) {
      case SortCriterion.name:
        return 'Name';
      case SortCriterion.created:
        return 'Created';
      case SortCriterion.modified:
        return 'Modified';
    }
  }

  String get _directionArrow =>
      sort.direction == SortDirection.desc ? '↓' : '↑';

  @override
  Widget build(BuildContext context) {
    final ream = context.ream;
    return PopupMenuButton<SortCriterion>(
      key: const Key('sort-pill'),
      onSelected: onCriterionSelected,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: ream.line),
      ),
      color: ream.surface,
      itemBuilder: (_) => [
        PopupMenuItem(
          key: const Key('sort-option-name'),
          value: SortCriterion.name,
          child: Text('Name', style: TextStyle(color: ream.ink2)),
        ),
        PopupMenuItem(
          key: const Key('sort-option-created'),
          value: SortCriterion.created,
          child: Text('Created', style: TextStyle(color: ream.ink2)),
        ),
        PopupMenuItem(
          key: const Key('sort-option-modified'),
          value: SortCriterion.modified,
          child: Text('Modified', style: TextStyle(color: ream.ink2)),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: ream.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ream.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _criterionLabel,
              style: TextStyle(
                color: ream.ink2,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              _directionArrow,
              style: TextStyle(
                color: ream.ink2,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
