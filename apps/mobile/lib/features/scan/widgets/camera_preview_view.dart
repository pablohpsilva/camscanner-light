import 'package:flutter/material.dart';

import '../camera_preview_controller.dart';

/// Frames the live preview with a shutter button. [onShutter] fires on tap;
/// while [capturing] is true the button shows progress and is disabled.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;
  final VoidCallback onShutter;
  final bool capturing;

  const CameraPreviewView({
    super.key,
    required this.controller,
    required this.onShutter,
    this.capturing = false,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: controller.buildPreview()),
          Positioned(
            bottom: 32,
            child: SizedBox(
              width: 72,
              height: 72,
              child: FloatingActionButton(
                key: const Key('scan-shutter'),
                heroTag: 'scan-shutter',
                onPressed: capturing ? null : onShutter,
                shape: const CircleBorder(),
                backgroundColor: Colors.white,
                child: capturing
                    ? const CircularProgressIndicator(
                        key: Key('scan-shutter-busy'))
                    : const Icon(Icons.camera_alt, color: Colors.black),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
