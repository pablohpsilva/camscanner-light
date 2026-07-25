import 'package:flutter/material.dart';
import '../app_colors.dart';

class AppSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const AppSegment({required this.value, required this.label, this.icon});
}

/// A compact segmented toggle in the App style (e.g. List / Grid).
class AppSegmented<T> extends StatelessWidget {
  final List<AppSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool expanded;
  const AppSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.expanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
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

  Widget _segment(BuildContext context, AppSegment<T> s) {
    final r = context.appColors;
    final selected = s.value == value;
    return GestureDetector(
      key: Key('segment-${s.value}'),
      onTap: () => onChanged(s.value),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 11,
          vertical: expanded ? 8 : 6,
        ),
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
