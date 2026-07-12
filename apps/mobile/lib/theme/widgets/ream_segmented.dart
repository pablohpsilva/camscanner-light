import 'package:flutter/material.dart';
import '../ream_colors.dart';

class ReamSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const ReamSegment({required this.value, required this.label, this.icon});
}

/// A compact segmented toggle in the Ream style (e.g. List / Grid).
class ReamSegmented<T> extends StatelessWidget {
  final List<ReamSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;
  const ReamSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: r.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: r.line),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final s in segments)
            if (expanded)
              Expanded(child: _segment(context, s))
            else
              _segment(context, s),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, ReamSegment<T> s) {
    final r = context.ream;
    final selected = s.value == value;
    return GestureDetector(
      key: Key('segment-${s.value}'),
      onTap: () => onChanged(s.value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? r.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          s.label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? r.surface : r.muted,
          ),
        ),
      ),
    );
  }
}
