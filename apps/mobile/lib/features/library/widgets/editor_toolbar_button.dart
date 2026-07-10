import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';

/// One item in the dark editor toolbar: an icon over a small label. [danger]
/// tints it red (Delete); a null [onPressed] dims and disables it.
class EditorToolbarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  const EditorToolbarButton({
    super.key,
    required this.icon,
    required this.label,
    this.onPressed,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final enabled = onPressed != null;
    final color = !enabled ? r.muted : (danger ? r.deleteRed : r.ink);
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Figtree',
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
