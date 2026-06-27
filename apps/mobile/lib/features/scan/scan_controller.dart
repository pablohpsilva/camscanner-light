import 'package:flutter/foundation.dart';

import 'camera_permission_service.dart';
import 'camera_preview_controller.dart';
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
