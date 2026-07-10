import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';

/// Dark top bar for the Ream document editor.
///
/// Provides a back button ([key: Key('page-viewer-back')]), a centered title,
/// and an optional [trailing] widget (e.g. an overflow-menu button). When
/// [trailing] is null a same-width [SizedBox] spacer is used so the title
/// remains visually centered.
///
/// Implements [PreferredSizeWidget] so it can be used as a [Scaffold.appBar].
class EditorTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;

  const EditorTopBar({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    // Measure the back button width so the spacer mirrors it exactly.
    const double sideWidth = kMinInteractiveDimension;

    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: ColoredBox(
          color: r.paper,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Back button — fixed width so the title can be truly centered.
              SizedBox(
                width: sideWidth,
                child: IconButton(
                  key: const Key('page-viewer-back'),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  color: r.ink,
                  onPressed: onBack,
                ),
              ),
              // Centered title.
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: r.ink,
                  ),
                ),
              ),
              // Trailing widget or symmetry spacer.
              SizedBox(
                width: sideWidth,
                child: trailing != null
                    ? Center(child: trailing)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
