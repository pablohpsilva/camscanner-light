import 'package:flutter/material.dart';
import '../app_colors.dart';
import '../app_typography.dart';

/// A mono, muted, letter-spaced caps section label (e.g. QUALITY, TYPE, MESSAGE).
class AppSectionLabel extends StatelessWidget {
  final String text;
  const AppSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    return Text(
      text.toUpperCase(),
      style: AppTypography.mono(
        size: 11,
        weight: FontWeight.w600,
        color: r.muted,
        letterSpacing: 0.3,
      ),
    );
  }
}
