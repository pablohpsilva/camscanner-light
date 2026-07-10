import 'package:flutter/material.dart';

import '../document_summary.dart';
import 'document_grid_card.dart';

/// A 2-column grid of saved documents, mirroring the public API of
/// [DocumentsListView] so callers can swap between list and grid without
/// touching any callback wiring.
///
/// Each cell maps to a [DocumentGridCard]. Tap behaviour mirrors
/// [DocumentsListView]: in selection mode a tap calls [onToggleSelect];
/// otherwise it calls [onOpen]. Long-press always calls [onLongPress].
class DocumentsGridView extends StatelessWidget {
  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  final Set<int> selectedIds;
  final bool selectionMode;
  final ValueChanged<DocumentSummary>? onToggleSelect;
  final ValueChanged<DocumentSummary>? onLongPress;

  const DocumentsGridView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
    this.onShare,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      key: const Key('documents-grid'),
      padding: const EdgeInsets.all(18),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.62,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
      ),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];
        return DocumentGridCard(
          summary: s,
          selected: selectedIds.contains(s.document.id),
          selectionMode: selectionMode,
          onTap: selectionMode
              ? (onToggleSelect == null ? null : () => onToggleSelect!(s))
              : (onOpen == null ? null : () => onOpen!(s)),
          onLongPress: onLongPress == null ? null : () => onLongPress!(s),
        );
      },
    );
  }
}
