import 'package:flutter/material.dart';
import '../app_colors.dart';

/// A App action button. [primary] is the filled green CTA (icon beside label);
/// secondary is an outlined surface tile (icon above label).
class AppActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  /// When false the [label] is not drawn as visible text; instead the button
  /// renders icon-only and exposes [label] through a [Tooltip] and a
  /// [Semantics] node (accessibility preserved). Fixes row overflow in long
  /// translations without shrinking any font. Defaults to true.
  final bool showLabel;

  /// Overrides the primary fill (default = greenDeep). No effect when secondary.
  final Color? fillColor;
  const AppActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.showLabel = true,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    final enabled = onPressed != null;
    final fill = primary ? (fillColor ?? r.greenDeep) : r.surface;
    final onPrimary = appInkOnFill(fill);
    final child = primary
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: onPrimary),
                if (showLabel) const SizedBox(width: 8),
              ],
              if (showLabel)
                Text(
                  label,
                  // Defensive: never let a long translation wrap the CTA.
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: onPrimary,
                  ),
                ),
            ],
          )
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: r.ink2),
                if (showLabel) const SizedBox(height: 3),
              ],
              if (showLabel)
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: r.ink2,
                  ),
                ),
            ],
          );
    Widget button = Material(
      color: fill,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 52,
          decoration: primary
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: r.line),
                ),
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
    // Icon-only: surface the label to pointer users (tooltip) and screen
    // readers (semantics) since there is no visible text.
    if (!showLabel) {
      button = Tooltip(
        message: label,
        child: Semantics(label: label, button: true, child: button),
      );
    }
    return Opacity(opacity: enabled ? 1 : 0.5, child: button);
  }
}
