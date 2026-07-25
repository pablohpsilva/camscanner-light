import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../l10n/l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_typography.dart';
import '../document_date_format.dart';
import '../document_summary.dart';
import '../feature_flags.dart';
import 'document_thumbnail.dart';
import 'share_menu_button.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Rendered in
/// the order it is given — the caller (HomeScreen) applies the user's chosen
/// sort (D3). Each row has an optional overflow menu (Rename / Share / Share
/// with password) when the matching callback is provided.
///
/// Swipe actions (C5, `flutter_slidable`): swipe RIGHT reveals Rename · Copy
/// text · Share · Share with password (each gated by its feature flag AND its
/// callback being provided); swipe LEFT reveals a single Delete that first opens
/// a confirm dialog (never an immediate delete). The 3-dots menu is kept for
/// users who don't swipe. Swipe is disabled in [selectionMode].
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

  /// Copies the document's recognized text to the clipboard (C5 swipe action).
  final ValueChanged<DocumentSummary>? onCopyText;

  /// Builds a password-protected PDF and shares it (C4b menu item + C5 swipe).
  final ValueChanged<DocumentSummary>? onProtect;

  /// Deletes the document (C5 swipe-left). Called ONLY after the user confirms
  /// the in-widget delete dialog — never an immediate delete.
  final ValueChanged<DocumentSummary>? onDelete;

  final Set<int> selectedIds;
  final bool selectionMode;
  final ValueChanged<DocumentSummary>? onToggleSelect;
  final ValueChanged<DocumentSummary>? onLongPress;
  final FeatureFlags features;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
    this.onShare,
    this.onCopyText,
    this.onProtect,
    this.onDelete,
    this.selectedIds = const {},
    this.selectionMode = false,
    this.onToggleSelect,
    this.onLongPress,
    this.features = const FeatureFlags(),
  });

  @override
  Widget build(BuildContext context) {
    // Auto-close an open row when another is swiped open, so at most one row's
    // actions are ever revealed at a time.
    return SlidableAutoCloseBehavior(
      child: ListView.builder(
        key: const Key('documents-list'),
        padding: const EdgeInsets.fromLTRB(12, 4, 12, fabBottomInset),
        itemCount: summaries.length,
        itemBuilder: (context, i) => _row(context, summaries[i]),
      ),
    );
  }

  Widget _row(BuildContext context, DocumentSummary s) {
    final r = context.appColors;
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
            tooltip: context.l10n.commonDocumentOptions,
            icon: Icon(Icons.more_horiz, color: r.muted),
            onSelected: (v) {
              if (v == 'rename') onRename?.call(s);
              if (v == 'share') onShare?.call(s);
              if (v == 'protect') onProtect?.call(s);
              if (v == kShareLinkValue || v == kFaxValue) {
                handleShareExtra(context, v);
              }
            },
            itemBuilder: (context) => [
              if (onShare != null)
                PopupMenuItem<String>(
                  key: Key('document-share-${d.id}'),
                  value: 'share',
                  child: Text(context.l10n.commonShare),
                ),
              if (onShare != null)
                ...shareExtraMenuItems(
                  context: context,
                  showFax: features.fax,
                  showShareLink: features.shareLink,
                  keyPrefix: 'document-${d.id}',
                ),
              if (onProtect != null && features.protectWithPassword)
                PopupMenuItem<String>(
                  key: Key('document-protect-${d.id}'),
                  value: 'protect',
                  child: Text(context.l10n.viewerShareProtect),
                ),
              if (onRename != null)
                PopupMenuItem<String>(
                  key: Key('document-rename-${d.id}'),
                  value: 'rename',
                  child: Text(context.l10n.commonRename),
                ),
            ],
          );

    final inner = Material(
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
                      '${context.l10n.commonPageCount(s.pageCount)} · '
                      '${formatDocumentDateDetailed(d.createdAt.toLocal(), Localizations.localeOf(context).toString())}',
                      style: AppTypography.mono(size: 11.5, color: r.muted),
                    ),
                  ],
                ),
              ),
              ?menu,
            ],
          ),
        ),
      ),
    );

    return Padding(
      key: Key('document-tile-${d.id}'),
      padding: const EdgeInsets.symmetric(vertical: 2),
      // Swipe is a non-selection affordance; in selection mode the row is a
      // checkbox target, so no Slidable is built.
      child: selectionMode ? inner : _slidable(context, s, inner),
    );
  }

  /// Wraps [inner] in a [Slidable]: swipe-right (startActionPane) reveals the
  /// enabled non-destructive actions; swipe-left (endActionPane) reveals Delete
  /// (confirm-gated). A pane is omitted entirely when it has no enabled action.
  Widget _slidable(BuildContext context, DocumentSummary s, Widget inner) {
    final r = context.appColors;
    final l10n = context.l10n;
    final id = s.document.id;

    final startActions = <Widget>[
      if (onRename != null && features.rename)
        SlidableAction(
          key: Key('document-slide-rename-$id'),
          onPressed: (_) => onRename!(s),
          icon: Icons.drive_file_rename_outline,
          label: l10n.commonRename,
          backgroundColor: r.surface2,
          foregroundColor: r.ink,
        ),
      if (onCopyText != null && features.viewText)
        SlidableAction(
          key: Key('document-slide-copytext-$id'),
          onPressed: (_) => onCopyText!(s),
          icon: Icons.content_copy_outlined,
          label: l10n.ocrCopyText,
          backgroundColor: r.blueSoft,
          foregroundColor: r.ink,
        ),
      if (onShare != null && features.share)
        SlidableAction(
          key: Key('document-slide-share-$id'),
          onPressed: (_) => onShare!(s),
          icon: Icons.ios_share,
          label: l10n.commonShare,
          backgroundColor: r.greenSoft,
          foregroundColor: r.ink,
        ),
      if (onProtect != null && features.protectWithPassword)
        SlidableAction(
          key: Key('document-slide-protect-$id'),
          onPressed: (_) => onProtect!(s),
          icon: Icons.lock_outline,
          label: l10n.viewerShareProtect,
          backgroundColor: r.amberSoft,
          foregroundColor: r.ink,
        ),
    ];

    final canDelete = onDelete != null && features.deleteDocument;

    return Slidable(
      key: Key('document-slidable-$id'),
      startActionPane: startActions.isEmpty
          ? null
          : ActionPane(
              motion: const DrawerMotion(),
              extentRatio: startActions.length >= 3 ? 0.9 : 0.5,
              children: startActions,
            ),
      endActionPane: !canDelete
          ? null
          : ActionPane(
              motion: const DrawerMotion(),
              extentRatio: 0.3,
              children: [
                SlidableAction(
                  key: Key('document-slide-delete-$id'),
                  onPressed: (ctx) => _confirmDelete(ctx, s),
                  icon: Icons.delete_outline,
                  label: l10n.commonDelete,
                  backgroundColor: r.deleteRed,
                  foregroundColor: Colors.white,
                ),
              ],
            ),
      child: inner,
    );
  }

  /// Confirms before deleting — the swipe reveals the action but the delete only
  /// happens once the user taps Delete in this dialog (cancel is a no-op).
  Future<void> _confirmDelete(BuildContext context, DocumentSummary s) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('document-delete-dialog'),
        content: Text(l10n.viewerDeleteDocumentConfirm),
        actions: [
          TextButton(
            key: const Key('document-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('document-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok == true) onDelete?.call(s);
  }
}
