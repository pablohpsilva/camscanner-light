import 'package:flutter/material.dart';
import '../../../theme/ream_colors.dart';
import '../../../theme/ream_typography.dart';

/// A small "N / M" page-counter pill overlaid on the editor viewer.
class PageCounterPill extends StatelessWidget {
  final int current; // 1-based
  final int total;
  const PageCounterPill({
    super.key,
    required this.current,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      child: Text(
        '$current / $total',
        style: ReamTypography.mono(
          size: 11,
          weight: FontWeight.w600,
          color: r.ink,
        ),
      ),
    );
  }
}
