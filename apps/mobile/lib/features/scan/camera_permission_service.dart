/// Result of asking for camera permission. [permanentlyDenied] means the OS
/// will not show a dialog again, so the only path forward is system Settings.
enum CameraPermissionStatus { granted, denied, permanentlyDenied }

/// Abstraction over the OS camera-permission flow (DIP). Production wires
/// `permission_handler`; tests inject a fake. The interface has no plugin
/// import, so widget/unit tests need no native bindings.
abstract interface class CameraPermissionService {
  /// Requests camera permission, returning the resolved status.
  Future<CameraPermissionStatus> request();

  /// Opens the OS app-settings page. Returns true if it was opened.
  Future<bool> openSettings();
}
