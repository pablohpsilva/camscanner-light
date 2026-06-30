import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'captured_image.dart';

/// Thrown when the device has no usable camera, or it fails to initialize.
class CameraUnavailableException implements Exception {
  final String message;
  const CameraUnavailableException(this.message);

  @override
  String toString() => 'CameraUnavailableException: $message';
}

/// Abstraction over the live camera preview (DIP). Production wraps the
/// `camera` plugin; tests inject a fake that paints a placeholder, so on-device
/// integration tests are deterministic without real camera hardware.
abstract interface class CameraPreviewController {
  /// Initializes the device camera. Throws [CameraUnavailableException] if no
  /// camera exists or initialization fails.
  Future<void> initialize();

  /// Builds the live preview widget. Only valid after [initialize] succeeds.
  Widget buildPreview();

  /// Captures a still image to a temporary file. Only valid after [initialize]
  /// succeeds. Throws [CameraUnavailableException] if capture fails.
  Future<CapturedImage> capture();

  /// Returns JPEG bytes of a sampled still frame, or null on any error.
  /// Only valid after [initialize()] succeeds. Never throws.
  Future<Uint8List?> sampleFrame();

  /// Camera native resolution in display-space coordinates — width and height
  /// are already swapped when sensor orientation is 90° or 270°. Valid after
  /// [initialize()] succeeds.
  Size get previewSize;

  /// Releases the camera.
  Future<void> dispose();
}
