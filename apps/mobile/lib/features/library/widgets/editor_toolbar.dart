import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';
import 'editor_toolbar_button.dart';

/// A 7-action dark bottom bar for the Ream document editor. Renders one
/// [EditorToolbarButton] per action, spaced evenly, on [ReamColors.paper] with
/// a hairline top border in [ReamColors.line]. A null callback disables that
/// button (passed through to [EditorToolbarButton]).
class EditorToolbar extends StatelessWidget {
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onText;
  final VoidCallback? onRetake;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onFilter;

  const EditorToolbar({
    super.key,
    required this.onCrop,
    required this.onRotate,
    required this.onText,
    required this.onRetake,
    required this.onShare,
    required this.onDelete,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: r.paper,
          border: Border(top: BorderSide(color: r.line)),
        ),
        child: Row(
          children: [
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-edit'),
                icon: Icons.crop,
                label: 'Crop',
                onPressed: onCrop,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-rotate'),
                icon: Icons.rotate_right,
                label: 'Rotate',
                onPressed: onRotate,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-filter'),
                icon: Icons.tune,
                label: 'Filter',
                onPressed: onFilter,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-view-text'),
                icon: Icons.text_snippet_outlined,
                label: 'Text',
                onPressed: onText,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-retake'),
                icon: Icons.replay,
                label: 'Retake',
                onPressed: onRetake,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-share'),
                icon: Icons.ios_share,
                label: 'Share',
                onPressed: onShare,
              ),
            ),
            Expanded(
              child: EditorToolbarButton(
                key: const Key('page-viewer-delete-page'),
                icon: Icons.delete_outline,
                label: 'Delete',
                danger: true,
                onPressed: onDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
