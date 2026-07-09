import 'package:permission_handler/permission_handler.dart';

/// Ensures runtime camera access before a [PhotoCamera] capture. Injectable
/// (DIP) so host tests never touch platform channels.
abstract interface class CameraPermission {
  /// Requests/checks camera permission. Returns true when the camera is
  /// usable, false when denied. Never throws.
  Future<bool> ensure();
}

/// Production gate backed by permission_handler. Required because the Android
/// manifest declares CAMERA, which image_picker's camera then requires at
/// runtime; iOS resolves against NSCameraUsageDescription.
class PermissionHandlerCameraPermission implements CameraPermission {
  const PermissionHandlerCameraPermission();
  @override
  Future<bool> ensure() async {
    try {
      final status = await Permission.camera.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }
}
