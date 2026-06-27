import 'package:flutter/material.dart';

/// Shown when camera permission is denied: a rationale and an Open Settings
/// action. The single button keeps the flow KISS for both denied states.
class PermissionDeniedView extends StatelessWidget {
  final bool permanentlyDenied;
  final Future<bool> Function() onOpenSettings;

  const PermissionDeniedView({
    super.key,
    required this.permanentlyDenied,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.no_photography_outlined, size: 64),
            const SizedBox(height: 16),
            const Text(
              'Camera access is needed to scan documents',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => onOpenSettings(),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}
