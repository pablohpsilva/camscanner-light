import 'camera_permission_service.dart';
import 'camera_permission_service_impl.dart';
import 'camera_preview_controller.dart';
import 'camera_preview_controller_impl.dart';
import 'edge_detector.dart';
import 'opencv_edge_detector.dart';

typedef CameraPermissionServiceFactory = CameraPermissionService Function();
typedef CameraPreviewControllerFactory = CameraPreviewController Function();
typedef EdgeDetectorFactory = EdgeDetector Function();

CameraPermissionService _defaultPermissionService() =>
    const PermissionHandlerCameraPermissionService();

CameraPreviewController _defaultPreviewController() =>
    PluginCameraPreviewController();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final CameraPermissionServiceFactory createPermissionService;
  final CameraPreviewControllerFactory createPreviewController;
  final EdgeDetectorFactory createEdgeDetector;

  const ScanDependencies({
    this.createPermissionService = _defaultPermissionService,
    this.createPreviewController = _defaultPreviewController,
    this.createEdgeDetector = _defaultEdgeDetector,
  });
}
