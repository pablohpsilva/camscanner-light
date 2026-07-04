import 'package:flutter/widgets.dart';

import 'camera_frame.dart';
import 'captured_image.dart';
import 'scan_flash_mode.dart';

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

  /// Starts delivering live preview frames to [onFrame]. No-op if already
  /// sampling. Never throws.
  void startSampling(void Function(CameraFrame frame) onFrame);

  /// Stops live-frame delivery. Safe when not sampling. Never throws.
  void stopSampling();

  /// Sets the flash/torch behavior. Never throws.
  Future<void> setFlashMode(ScanFlashMode mode);

  /// Camera native resolution in display-space coordinates — width and height
  /// are already swapped when sensor orientation is 90° or 270°. Valid after
  /// [initialize()] succeeds.
  Size get previewSize;

  /// Releases the camera.
  Future<void> dispose();
}
