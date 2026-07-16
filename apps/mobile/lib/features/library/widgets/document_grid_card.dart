import 'package:flutter/material.dart';
import 'package:mobile/features/library/document_date_format.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/document_thumbnail.dart';
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
class DocumentGridCard extends StatelessWidget {
  const DocumentGridCard({
    required this.summary,
    this.onTap,
    this.onLongPress,
    this.selected = false,
    this.selectionMode = false,
    super.key,
  });

  final DocumentSummary summary;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool selected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final ream = context.ream;
    final textTheme = Theme.of(context).textTheme;
    final doc = summary.document;

    // createdAt (matching the list) + locale-aware compact date (P15).
    final shortDate = formatDocumentDateCompact(
      doc.createdAt.toLocal(),
      Localizations.localeOf(context).toString(),
    );
    final metaText = '${summary.pageCount}p · $shortDate';

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
              color: kReamCardShadow,
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
