import 'package:flutter/material.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/widgets/document_thumbnail.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';
import 'package:mobile/features/library/widgets/tag_chips.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_typography.dart';

/// A grid card for a document in the library grid view.
///
/// Shows a thumbnail area (aspect ratio ~0.77), the document title, and a mono
/// meta line with the page count and short date. Wraps in a [GestureDetector]
/// keyed as `document-card-<id>`. When [selected] is true, a check badge is
/// shown.
///
/// Intended for use inside a [GridView] cell (which constrains width). In that
/// context the thumbnail area fills the width at a ~0.77 portrait ratio. The
/// card is self-sizing (no fixed outer width required).
///
/// Optional per-card overflow menu (Share / Rename / Move to folder / Tags…),
/// keyed the same way as [DocumentsListView]'s row menu
/// (`document-menu-<id>`, `document-share-<id>`, etc.) so BDD/step code can
/// target either view generically. The menu lives directly on the card
/// (rather than as a Positioned overlay in DocumentsGridView) — this keeps
/// the diff smallest: DocumentsGridView already threads onRename/onShare
/// straight through to this card's constructor, so this card is the natural
/// single owner of "does this document have a menu, and what's in it."
class DocumentGridCard extends StatelessWidget {
  const DocumentGridCard({
    required this.summary,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    this.showTags = true,
    this.onRename,
    this.onShare,
    this.onMoveToFolder,
    this.onManageTags,
    this.features = const FeatureFlags(),
    super.key,
  });

  final DocumentSummary summary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;
  final bool showTags;
  final ValueChanged<DocumentSummary>? onRename;
  final ValueChanged<DocumentSummary>? onShare;
  final ValueChanged<DocumentSummary>? onMoveToFolder;
  final ValueChanged<DocumentSummary>? onManageTags;
  final FeatureFlags features;

  @override
  Widget build(BuildContext context) {
    final ream = context.ream;
    final textTheme = Theme.of(context).textTheme;
    final doc = summary.document;

    final shortDate = _formatDate(doc.modifiedAt);
    final metaText = '${summary.pageCount}p · $shortDate';

    final showMoveToFolder = features.folders && onMoveToFolder != null;
    final showManageTags = features.tags && onManageTags != null;
    final menu =
        (selectionMode ||
            (onRename == null &&
                onShare == null &&
                !showMoveToFolder &&
                !showManageTags))
        ? null
        : PopupMenuButton<String>(
            key: Key('document-menu-${doc.id}'),
            tooltip: 'Document options',
            icon: const Icon(Icons.more_horiz, color: Colors.white),
            onSelected: (v) {
              if (v == 'rename') onRename?.call(summary);
              if (v == 'share') onShare?.call(summary);
              if (v == 'move') onMoveToFolder?.call(summary);
              if (v == 'tags') onManageTags?.call(summary);
              if (v == kShareLinkValue || v == kFaxValue) {
                handleShareExtra(context, v);
              }
            },
            itemBuilder: (context) => [
              if (onShare != null)
                PopupMenuItem<String>(
                  key: Key('document-share-${doc.id}'),
                  value: 'share',
                  child: const Text('Share'),
                ),
              if (onShare != null)
                ...shareExtraMenuItems(
                  showFax: features.fax,
                  showShareLink: features.shareLink,
                  keyPrefix: 'document-${doc.id}',
                ),
              if (onRename != null)
                PopupMenuItem<String>(
                  key: Key('document-rename-${doc.id}'),
                  value: 'rename',
                  child: const Text('Rename'),
                ),
              if (showMoveToFolder)
                PopupMenuItem<String>(
                  key: Key('document-move-${doc.id}'),
                  value: 'move',
                  child: const Text('Move to folder'),
                ),
              if (showManageTags)
                PopupMenuItem<String>(
                  key: Key('document-tags-${doc.id}'),
                  value: 'tags',
                  child: const Text('Tags…'),
                ),
            ],
          );

    // The card uses an IntrinsicWidth to make the thumbnail's AspectRatio
    // derive a sensible height.  In a GridView cell the cell width constrains
    // things naturally; IntrinsicWidth wraps to the minimum allowed width
    // (minWidth) when placed in an unconstrained parent (e.g., Scaffold body in
    // widget tests) so the layout doesn't overflow.
    Widget card = IntrinsicWidth(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ream.surface,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: ream.line, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Thumbnail area: portrait page shape (~0.77 aspect ratio).
              AspectRatio(
                aspectRatio: 0.77,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _ThumbnailArea(
                      path: summary.thumbnailPath,
                      backgroundColor: ream.surface2,
                    ),
                    if (selected)
                      Positioned(
                        top: 6,
                        right: 6,
                        child: Icon(
                          Icons.check_circle,
                          color: ream.green,
                          size: 22,
                        ),
                      ),
                    if (menu != null)
                      Positioned(
                        top: -6,
                        right: -6,
                        // Absorb the tap here so it does not also fire onTap
                        // (opening the document) — GestureDetector.onTap on
                        // the outer card and the PopupMenuButton's tap both
                        // sit in the same hit-test chain otherwise.
                        child: GestureDetector(
                          onTap: () {},
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.35),
                              shape: BoxShape.circle,
                            ),
                            child: menu,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Footer: title + meta
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      doc.name,
                      style: textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      metaText,
                      style: ReamTypography.mono(size: 11, color: ream.muted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showTags && summary.tags.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      TagChips(tags: summary.tags),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return GestureDetector(
      key: Key('document-card-${doc.id}'),
      onTap: onTap,
      onLongPress: onLongPress,
      child: card,
    );
  }

  static String _formatDate(DateTime dt) {
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dt.month - 1]} ${dt.day}';
  }
}

/// Fills the thumbnail area: shows [DocumentThumbnail] sized to fill, or a
/// neutral placeholder when [path] is null.
class _ThumbnailArea extends StatelessWidget {
  const _ThumbnailArea({required this.path, required this.backgroundColor});

  final String? path;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    if (path == null) {
      return ColoredBox(
        color: backgroundColor,
        child: Center(
          child: Icon(
            Icons.description_outlined,
            color: context.ream.muted,
            size: 36,
          ),
        ),
      );
    }
    return DocumentThumbnail(path: path, size: double.infinity);
  }
}
