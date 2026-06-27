import 'dart:io';

import 'package:flutter/material.dart';

import 'captured_image.dart';

/// Shows a freshly captured [image] with Retake / Accept actions. Stateless —
/// the parent decides what Retake and Accept do (navigation). A3: Retake
/// returns to the live preview; Accept returns to the Documents home (no save
/// yet — persistence is B1).
class CaptureReviewScreen extends StatelessWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final VoidCallback onAccept;

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: ColoredBox(
        color: Colors.black,
        child: Center(
          child: Image.file(
            File(image.path),
            key: const Key('review-image'),
            fit: BoxFit.contain,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.broken_image_outlined,
              key: Key('review-image-error'),
              color: Colors.white54,
              size: 64,
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                key: const Key('review-retake'),
                onPressed: onRetake,
                icon: const Icon(Icons.replay),
                label: const Text('Retake'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: onAccept,
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
