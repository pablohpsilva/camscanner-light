import 'package:flutter/material.dart';
import '../ream_colors.dart';

/// A Ream action button. [primary] is the filled green CTA (icon beside label);
/// secondary is an outlined surface tile (icon above label).
class ReamActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;

  /// Overrides the primary fill (default = greenDeep). No effect when secondary.
  final Color? fillColor;
  const ReamActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final enabled = onPressed != null;
    final fill = primary ? (fillColor ?? r.greenDeep) : r.surface;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
        ? Colors.white
        : const Color(0xFF201C16); // warm near-black for light fills
    final child = primary
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: onPrimary),
                const SizedBox(width: 8),
              ],
              Text(
                label,
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
                const SizedBox(height: 3),
              ],
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
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
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
      ),
    );
  }
}
