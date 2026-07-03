import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_frame.dart';
import 'camera_preview_controller.dart';
import 'captured_image.dart';
import 'scan_flash_mode.dart';

/// Production [CameraPreviewController] backed by the `camera` plugin.
class PluginCameraPreviewController implements CameraPreviewController {
  PluginCameraPreviewController();

  CameraController? _controller;
  bool _takingPicture = false;

  void Function(CameraFrame)? _onFrame;
  bool _streaming = false;
  final Stopwatch _throttle = Stopwatch();
  ScanFlashMode _flash = ScanFlashMode.off;
  static const _kMinSampleGapMs = 700;

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
      // Documents need high resolution; ResolutionPreset.high is only 720p,
      // which makes captured text soft and hard to read. ultraHigh (~2160p)
      // is much sharper while staying below the heaviest (max) preset.
      ResolutionPreset.ultraHigh,
      enableAudio: false,
      imageFormatGroup:
          Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
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
      if (_flash == ScanFlashMode.flash) {
        await controller.setFlashMode(FlashMode.always);
      }
      final file = await controller.takePicture();
      return CapturedImage(file.path);
    } on CameraException catch (e) {
      throw CameraUnavailableException(e.description ?? e.code);
    } finally {
      _takingPicture = false;
      if (_flash == ScanFlashMode.flash) {
        await controller.setFlashMode(FlashMode.off).catchError((_) {});
      }
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
  void startSampling(void Function(CameraFrame frame) onFrame) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    _onFrame = onFrame;
    if (_streaming) return;
    _streaming = true;
    _throttle
      ..reset()
      ..start();
    var first = true;
    controller.startImageStream((image) {
      if (!_streaming) return;
      if (!first && _throttle.elapsedMilliseconds < _kMinSampleGapMs) return;
      first = false;
      _throttle.reset();
      final frame = _mapFrame(image);
      if (frame != null) _onFrame?.call(frame);
    }).catchError((_) {
      _streaming = false;
    });
  }

  @override
  void stopSampling() {
    _onFrame = null;
    if (!_streaming) return;
    _streaming = false;
    _controller?.stopImageStream().catchError((_) {});
  }

  CameraFrame? _mapFrame(CameraImage image) {
    final group = image.format.group;
    final CameraFrameFormat fmt;
    if (group == ImageFormatGroup.bgra8888) {
      fmt = CameraFrameFormat.bgra8888;
    } else if (group == ImageFormatGroup.yuv420) {
      fmt = CameraFrameFormat.yuv420;
    } else {
      return null;
    }
    return CameraFrame(
      width: image.width,
      height: image.height,
      format: fmt,
      planes: image.planes
          .map((p) => CameraFramePlane(
                bytes: p.bytes,
                bytesPerRow: p.bytesPerRow,
                bytesPerPixel: p.bytesPerPixel,
              ))
          .toList(growable: false),
    );
  }

  @override
  Future<void> setFlashMode(ScanFlashMode mode) async {
    _flash = mode;
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      // Torch lights immediately; off/flash keep the LED dark during preview
      // (flash fires only at capture, applied in capture()).
      await controller.setFlashMode(
        mode == ScanFlashMode.torch ? FlashMode.torch : FlashMode.off,
      );
    } on CameraException {
      // never throws
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
