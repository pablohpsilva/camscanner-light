import 'package:flutter/material.dart';

import '../../../theme/ream_colors.dart';
import '../../../theme/ream_typography.dart';
import '../document_summary.dart';
import 'document_thumbnail.dart';
import 'share_menu_button.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Rendered in
/// the order it is given — the caller (HomeScreen) applies the user's chosen
/// sort (D3). Each row has an optional overflow menu (Rename / Share) when
/// [onRename] or [onShare] is provided.
///
/// Opt-in multi-select: when [selectionMode] is true, rows show a checkbox and
/// a tap routes to [onToggleSelect] (not [onOpen]); [onLongPress] enters the
/// mode from the caller. All selection params default to a no-op so existing
/// callers and tests are unaffected.
class DocumentsListView extends StatelessWidget {
  /// Bottom scroll inset (~ one row's height) so the floating Scan button,
  /// which docks over the bottom-right of this list, never permanently covers
  /// the last row's overflow (⋮) menu — the user can scroll it into the clear.
  static const double fabBottomInset = 88;

  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  final Set<int> selectedIds;
  final bool selectionMode;
  final ValueChanged<DocumentSummary>? onToggleSelect;
  final ValueChanged<DocumentSummary>? onLongPress;
  const DocumentsListView({
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
    return ListView.builder(
      key: const Key('documents-list'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, fabBottomInset),
      itemCount: summaries.length,
      itemBuilder: (context, i) => _row(context, summaries[i]),
    );
  }

  Widget _row(BuildContext context, DocumentSummary s) {
    final r = context.ream;
    final d = s.document;
    final selected = selectedIds.contains(d.id);
    final theme = Theme.of(context);

    final leading = selectionMode
        ? Icon(
            selected ? Icons.check_circle : Icons.circle_outlined,
            key: Key('document-check-${d.id}'),
            color: selected ? r.greenDeep : r.muted,
          )
        : Container(
            decoration: BoxDecoration(
              color: r.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: r.line),
            ),
            padding: const EdgeInsets.all(2),
            child: DocumentThumbnail(
              key: Key('document-thumb-${d.id}'),
              path: s.thumbnailPath,
            ),
          );

    final menu = (selectionMode || (onRename == null && onShare == null))
        ? null
        : PopupMenuButton<String>(
            key: Key('document-menu-${d.id}'),
            tooltip: 'Document options',
            icon: Icon(Icons.more_horiz, color: r.muted),
            onSelected: (v) {
              if (v == 'rename') onRename?.call(s);
              if (v == 'share') onShare?.call(s);
              if (v == kShareLinkValue || v == kFaxValue) {
                handleShareExtra(context, v);
              }
            },
            itemBuilder: (context) => [
              if (onShare != null)
                PopupMenuItem<String>(
                  key: Key('document-share-${d.id}'),
                  value: 'share',
                  child: const Text('Share'),
                ),
              if (onShare != null)
                ...shareExtraMenuItems(
                  showFax: true,
                  keyPrefix: 'document-${d.id}',
                ),
              if (onRename != null)
                PopupMenuItem<String>(
                  key: Key('document-rename-${d.id}'),
                  value: 'rename',
                  child: const Text('Rename'),
                ),
            ],
          );

    return Padding(
      key: Key('document-tile-${d.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selectionMode && selected ? r.surface : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onLongPress: onLongPress == null ? null : () => onLongPress!(s),
          onTap: selectionMode
              ? (onToggleSelect == null ? null : () => onToggleSelect!(s))
              : (onOpen == null ? null : () => onOpen!(s)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
            child: Row(
              children: [
                leading,
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        d.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${_formatLocal(d.createdAt.toLocal())} · '
                        '${_pages(s.pageCount)}',
                        style: ReamTypography.mono(size: 11.5, color: r.muted),
                      ),
                    ],
                  ),
                ),
                ?menu,
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
