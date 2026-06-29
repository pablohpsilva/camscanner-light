import 'package:permission_handler/permission_handler.dart' as ph;

import 'camera_permission_service.dart';

/// Production [CameraPermissionService] backed by `permission_handler`.
class PermissionHandlerCameraPermissionService
    implements CameraPermissionService {
  const PermissionHandlerCameraPermissionService();

  @override
  Future<CameraPermissionStatus> request() async {
    final status = await ph.Permission.camera.request();
    if (status.isGranted || status.isLimited) {
      return CameraPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return CameraPermissionStatus.permanentlyDenied;
    }
    return CameraPermissionStatus.denied;
  }

  @override
  Future<bool> openSettings() => ph.openAppSettings();
}
