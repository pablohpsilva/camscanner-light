import 'package:flutter/material.dart';
import '../ream_colors.dart';

/// Inline, always-visible search field in the Ream header style.
class ReamSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final VoidCallback? onClear;
  const ReamSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search titles & text inside pages',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: r.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: r.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(
        children: [
          Icon(Icons.search, size: 18, color: r.muted),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              key: const Key('documents-search-field'),
              controller: controller,
              onChanged: onChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: r.ink, fontSize: 14),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                hintText: hintText,
                hintStyle: TextStyle(color: r.muted, fontSize: 13.5),
                border: InputBorder.none,
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.isEmpty) return const SizedBox.shrink();
              return GestureDetector(
                key: const Key('documents-search-clear'),
                onTap: () {
                  controller.clear();
                  onChanged('');
                  onClear?.call();
                },
                child: Icon(Icons.close, size: 16, color: r.muted),
              );
            },
          ),
        ],
      ),
    );
  }
}
