import 'package:flutter/material.dart';

import '../camera_preview_controller.dart';

/// Frames the live preview produced by [controller] on a black backdrop.
class CameraPreviewView extends StatelessWidget {
  final CameraPreviewController controller;

  const CameraPreviewView({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(child: controller.buildPreview()),
    );
  }
}
