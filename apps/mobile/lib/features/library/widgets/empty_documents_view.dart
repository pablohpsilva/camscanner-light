import 'package:flutter/material.dart';

/// Shown in the library when the user has no documents yet.
class EmptyDocumentsView extends StatelessWidget {
  const EmptyDocumentsView({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 72, color: muted),
          const SizedBox(height: 16),
          const Text(
            'No documents yet',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap Scan to create your first document',
            style: TextStyle(color: muted),
          ),
        ],
      ),
    );
  }
}
