import 'package:flutter/material.dart';
import '../ream_colors.dart';
import '../ream_typography.dart';

enum ConfidenceLevel { high, verify, info }

/// A rounded status pill using the confidence trio: green (high), amber
/// (verify), blue (info). A leading dot + label.
class ConfidenceChip extends StatelessWidget {
  final ConfidenceLevel level;
  final String label;
  const ConfidenceChip({super.key, required this.level, required this.label});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final (dot, fg, bg) = switch (level) {
      ConfidenceLevel.high => (r.green, r.greenDeep, r.greenSoft),
      ConfidenceLevel.verify => (r.amber, r.ink2, r.amberSoft),
      ConfidenceLevel.info => (r.blue, r.ink2, r.blueSoft),
    };
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dot),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            key: const Key('confidence-dot'),
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            child: const SizedBox(width: 7, height: 7),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: ReamTypography.mono(
              size: 12,
              weight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
