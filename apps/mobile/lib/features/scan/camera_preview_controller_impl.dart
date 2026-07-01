import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_preview_controller.dart';
import 'captured_image.dart';

/// Production [CameraPreviewController] backed by the `camera` plugin.
class PluginCameraPreviewController implements CameraPreviewController {
  PluginCameraPreviewController();

  CameraController? _controller;
  bool _takingPicture = false;

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
    // A live-detection sample may have a takePicture in flight; the camera plugin
    // rejects concurrent captures. Wait (bounded) for it to clear, then claim the
    // camera. Single-threaded Dart makes the check-then-set between awaits atomic.
    var waited = 0;
    while (_takingPicture && waited < 3000) {
      await Future.delayed(const Duration(milliseconds: 25));
      waited += 25;
    }
    _takingPicture = true;
    try {
      final file = await controller.takePicture();
      return CapturedImage(file.path);
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    } finally {
      _takingPicture = false;
    }
  }

  @override
  Future<Uint8List?> sampleFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return null;
    if (_takingPicture) return null;
    _takingPicture = true;
    try {
      final file = await controller.takePicture();
      final bytes = await File(file.path).readAsBytes();
      await File(file.path).delete();
      return bytes;
    } catch (_) {
      return null;
    } finally {
      _takingPicture = false;
    }
  }

  @override
  Size get previewSize {
    final controller = _controller!;
    final size = controller.value.previewSize!;
    final rot = controller.description.sensorOrientation;
    return (rot == 90 || rot == 270)
        ? Size(size.height, size.width)
        : size;
  }

  @override
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}
