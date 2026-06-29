import 'camera_permission_service.dart';
import 'camera_permission_service_impl.dart';
import 'camera_preview_controller.dart';
import 'camera_preview_controller_impl.dart';

typedef CameraPermissionServiceFactory = CameraPermissionService Function();
typedef CameraPreviewControllerFactory = CameraPreviewController Function();

CameraPermissionService _defaultPermissionService() =>
    const PermissionHandlerCameraPermissionService();

CameraPreviewController _defaultPreviewController() =>
    PluginCameraPreviewController();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final CameraPermissionServiceFactory createPermissionService;
  final CameraPreviewControllerFactory createPreviewController;

  const ScanDependencies({
    this.createPermissionService = _defaultPermissionService,
    this.createPreviewController = _defaultPreviewController,
  });
}
