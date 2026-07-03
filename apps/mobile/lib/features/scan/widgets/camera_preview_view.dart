import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';
import '../camera_preview_controller.dart';
import '../scan_flash_mode.dart';
import 'live_quad_overlay.dart';

/// Frames the live preview with a shutter button. [onShutter] fires on tap;
/// while [capturing] is true the button shows progress and is disabled.
/// When [liveCorners] and [previewSize] are both non-null, draws a
/// [LiveQuadOverlay] (green quad, non-interactive) over the preview.
/// [flashMode] controls the icon shown on the flash toggle (top-trailing);
/// [onFlashModeChanged] is called with the next mode when the button is tapped.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;
  final VoidCallback onShutter;
  final bool capturing;
  final CropCorners? liveCorners;
  final Size? previewSize;
  final ScanFlashMode flashMode;
  final ValueChanged<ScanFlashMode>? onFlashModeChanged;

  const CameraPreviewView({
    super.key,
    required this.controller,
    required this.onShutter,
    this.capturing = false,
    this.liveCorners,
    this.previewSize,
    this.flashMode = ScanFlashMode.off,
    this.onFlashModeChanged,
  });

  IconData get _flashIcon => switch (flashMode) {
        ScanFlashMode.off => Icons.flash_off,
        ScanFlashMode.torch => Icons.flashlight_on,
        ScanFlashMode.flash => Icons.flash_on,
      };

  ScanFlashMode get _nextFlash => switch (flashMode) {
        ScanFlashMode.off => ScanFlashMode.torch,
        ScanFlashMode.torch => ScanFlashMode.flash,
        ScanFlashMode.flash => ScanFlashMode.off,
      };

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
            top: 16 + MediaQuery.of(context).viewPadding.top,
            right: 16,
            child: IconButton(
              key: const Key('scan-flash-toggle'),
              icon: Icon(_flashIcon, color: Colors.white, size: 28),
              onPressed: () => onFlashModeChanged?.call(_nextFlash),
            ),
          ),
          Positioned(
            // Lift the shutter above the system navigation bar: the preview is
            // full-bleed (no SafeArea), so a fixed 32px would sit BEHIND an
            // on-screen nav bar on devices that have one, hiding the button.
            bottom: 32 + MediaQuery.of(context).viewPadding.bottom,
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
