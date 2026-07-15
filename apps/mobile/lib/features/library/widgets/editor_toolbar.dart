import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/ream_colors.dart';
import 'editor_toolbar_button.dart';

/// A 7-action dark bottom bar for the Ream document editor. Renders one
/// [EditorToolbarButton] per action, spaced evenly, on [ReamColors.paper] with
/// a hairline top border in [ReamColors.line]. A null callback disables that
/// button (passed through to [EditorToolbarButton]); a false show* flag omits
/// that button entirely and the row reflows.
class EditorToolbar extends StatelessWidget {
  final VoidCallback? onCrop;
  final VoidCallback? onRotate;
  final VoidCallback? onText;
  final VoidCallback? onRetake;
  final VoidCallback? onShare;
  final VoidCallback? onDelete;
  final VoidCallback? onFilter;
  final bool showCrop;
  final bool showRotate;
  final bool showFilter;
  final bool showText;
  final bool showRetake;
  final bool showShare;
  final bool showDelete;

  const EditorToolbar({
    super.key,
    required this.onCrop,
    required this.onRotate,
    required this.onText,
    required this.onRetake,
    required this.onShare,
    required this.onDelete,
    required this.onFilter,
    this.showCrop = true,
    this.showRotate = true,
    this.showFilter = true,
    this.showText = true,
    this.showRetake = true,
    this.showShare = true,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final l10n = context.l10n;
    final buttons = <Widget>[
      if (showCrop)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-edit'),
            icon: Icons.crop,
            label: l10n.toolbarCrop,
            onPressed: onCrop,
          ),
        ),
      if (showRotate)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-rotate'),
            icon: Icons.rotate_right,
            label: l10n.toolbarRotate,
            onPressed: onRotate,
          ),
        ),
      if (showFilter)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-filter'),
            icon: Icons.tune,
            label: l10n.toolbarFilter,
            onPressed: onFilter,
          ),
        ),
      if (showText)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-view-text'),
            icon: Icons.text_snippet_outlined,
            label: l10n.toolbarText,
            onPressed: onText,
          ),
        ),
      if (showRetake)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-retake'),
            icon: Icons.replay,
            label: l10n.commonRetake,
            onPressed: onRetake,
          ),
        ),
      if (showShare)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-share'),
            icon: Icons.ios_share,
            label: l10n.commonShare,
            onPressed: onShare,
          ),
        ),
      if (showDelete)
        Expanded(
          child: EditorToolbarButton(
            key: const Key('page-viewer-delete-page'),
            icon: Icons.delete_outline,
            label: l10n.commonDelete,
            danger: true,
            onPressed: onDelete,
          ),
        ),
    ];
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: r.paper,
          border: Border(top: BorderSide(color: r.line)),
        ),
        child: Row(children: buttons),
      ),
    );
  }
}
