import 'package:flutter/foundation.dart';

import 'camera_permission_service.dart';
import 'camera_preview_controller.dart';
import 'captured_image.dart';
import 'scan_view_state.dart';

/// Orchestrates the Scan screen's state machine:
/// `checking → ready | permissionDenied | unavailable`.
///
/// Holds no widgets — it is unit-testable with fakes. The screen listens to it
/// and renders one view per [status].
class ScanController extends ChangeNotifier {
  final CameraPermissionService _permission;
  final CameraPreviewController _preview;

  ScanController({
    required CameraPermissionService permission,
    required CameraPreviewController preview,
  })  : _permission = permission, // ignore: prefer_initializing_formals
        _preview = preview; // ignore: prefer_initializing_formals

  ScanStatus _status = ScanStatus.checking;
  ScanStatus get status => _status;

  bool _permanentlyDenied = false;
  bool get permanentlyDenied => _permanentlyDenied;

  bool _capturing = false;
  bool get capturing => _capturing;

  bool _disposed = false;

  /// The preview controller, valid for [ScanStatus.ready].
  CameraPreviewController get preview => _preview;

  /// Requests permission and initializes the camera, resolving [status].
  Future<void> start() async {
    _set(ScanStatus.checking);
    final permission = await _permission.request();
    if (_disposed) return;
    if (permission == CameraPermissionStatus.granted) {
      try {
        await _preview.initialize();
        if (_disposed) {
          await _preview.dispose(); // release the camera initialized after disposal
          return;
        }
        _set(ScanStatus.ready);
      } on CameraUnavailableException {
        if (_disposed) return;
        _set(ScanStatus.unavailable);
      }
    } else {
      _permanentlyDenied =
          permission == CameraPermissionStatus.permanentlyDenied;
      _set(ScanStatus.permissionDenied);
    }
  }

  /// Opens the OS settings page (for the denied state).
  Future<bool> openSettings() => _permission.openSettings();

  /// Captures a still image in the ready state. Returns null if not ready,
  /// already capturing, disposed, or capture failed (the screen surfaces
  /// failure). Sets [capturing] true→false around the in-flight capture.
  Future<CapturedImage?> capture() async {
    if (_disposed || _status != ScanStatus.ready || _capturing) return null;
    _capturing = true;
    notifyListeners();
    try {
      final image = await _preview.capture();
      if (_disposed) return null;
      return image;
    } on CameraUnavailableException {
      return null;
    } finally {
      if (!_disposed) {
        _capturing = false;
        notifyListeners();
      }
    }
  }

  void _set(ScanStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _preview.dispose();
    super.dispose();
  }
}
