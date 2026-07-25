import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_colors.dart';

/// Shared back-header for App screens: leading chevron, centered Figtree-700
/// title, trailing spacer (or [trailing]) for symmetry. Reads [context.appColors]
/// so it renders correctly under both light and dark App themes.
class AppBackHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Key? backKey;
  const AppBackHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backKey,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    const double sideWidth = kMinInteractiveDimension;
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: kToolbarHeight,
          child: ColoredBox(
            color: r.paper,
            child: Row(
              children: [
                SizedBox(
                  width: sideWidth,
                  child: IconButton(
                    key: backKey ?? const Key('back'),
                    icon: const Icon(Icons.arrow_back_ios_new),
                    color: r.ink,
                    onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                ),
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
      ),
    );
  }
}
