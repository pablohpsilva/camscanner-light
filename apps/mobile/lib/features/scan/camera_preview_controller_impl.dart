import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_preview_controller.dart';
import 'captured_image.dart';

/// Production [CameraPreviewController] backed by the `camera` plugin.
class PluginCameraPreviewController implements CameraPreviewController {
  PluginCameraPreviewController();

  CameraController? _controller;

  @override
  Future<void> initialize() async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    }
    if (cameras.isEmpty) {
      throw const CameraUnavailableException('No camera available');
    }
    final controller = CameraController(
      cameras.first,
      ResolutionPreset.high,
      enableAudio: false,
    );
    try {
      await controller.initialize();
    } on CameraException catch (e) {
      await controller.dispose();
      throw CameraUnavailableException(e.description ?? e.code);
    }
    _controller = controller;
  }

  @override
  Widget buildPreview() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw StateError('buildPreview() called before initialize() succeeded');
    }
    return CameraPreview(controller);
  }

  @override
  Future<CapturedImage> capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      throw const CameraUnavailableException('capture() before initialize()');
    }
    try {
      final file = await controller.takePicture();
      return CapturedImage(file.path);
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    }
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
