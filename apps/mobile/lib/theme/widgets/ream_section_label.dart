import 'package:flutter/material.dart';
import '../ream_colors.dart';
import '../ream_typography.dart';

/// A mono, muted, letter-spaced caps section label (e.g. QUALITY, TYPE, MESSAGE).
class ReamSectionLabel extends StatelessWidget {
  final String text;
  const ReamSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Text(
      text.toUpperCase(),
      style: ReamTypography.mono(
        size: 11,
        weight: FontWeight.w600,
        color: r.muted,
        letterSpacing: 0.3,
      ),
    );
  }
}
