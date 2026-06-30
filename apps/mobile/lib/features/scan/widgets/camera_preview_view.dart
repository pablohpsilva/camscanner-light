import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';
import '../camera_preview_controller.dart';
import 'live_quad_overlay.dart';

/// Frames the live preview with a shutter button. [onShutter] fires on tap;
/// while [capturing] is true the button shows progress and is disabled.
/// When [liveCorners] and [previewSize] are both non-null, draws a
/// [LiveQuadOverlay] (green quad, non-interactive) over the preview.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;
  final VoidCallback onShutter;
  final bool capturing;
  final CropCorners? liveCorners;
  final Size? previewSize;

  const CameraPreviewView({
    super.key,
    required this.controller,
    required this.onShutter,
    this.capturing = false,
    this.liveCorners,
    this.previewSize,
  });

  @override
  Widget build(BuildContext context) {
    final corners = liveCorners;
    final size = previewSize;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(child: controller.buildPreview()),
          if (corners != null && size != null)
            IgnorePointer(
              child: LiveQuadOverlay(
                corners: corners,
                previewSize: size,
                color: Colors.green,
              ),
            ),
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
