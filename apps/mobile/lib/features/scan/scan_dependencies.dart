import 'camera_permission_service.dart';
import 'camera_permission_service_impl.dart';
import 'camera_preview_controller.dart';
import 'camera_preview_controller_impl.dart';
import 'cunning_document_scanner_service.dart';
import 'document_scanner_service.dart';
import 'edge_detector.dart';
import 'gallery_picker.dart';
import 'opencv_edge_detector.dart';

typedef CameraPermissionServiceFactory = CameraPermissionService Function();
typedef CameraPreviewControllerFactory = CameraPreviewController Function();
typedef DocumentScannerServiceFactory = DocumentScannerService Function();
typedef EdgeDetectorFactory = EdgeDetector Function();
typedef GalleryPickerFactory = GalleryPicker Function();

CameraPermissionService _defaultPermissionService() =>
    const PermissionHandlerCameraPermissionService();

CameraPreviewController _defaultPreviewController() =>
    PluginCameraPreviewController();

DocumentScannerService _defaultDocumentScanner() =>
    const CunningDocumentScannerService();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

GalleryPicker _defaultGalleryPicker() => const ImagePickerGalleryPicker();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final CameraPermissionServiceFactory createPermissionService;
  final CameraPreviewControllerFactory createPreviewController;
  final DocumentScannerServiceFactory createDocumentScanner;
  final EdgeDetectorFactory createEdgeDetector;
  final GalleryPickerFactory createGalleryPicker;

  const ScanDependencies({
    this.createPermissionService = _defaultPermissionService,
    this.createPreviewController = _defaultPreviewController,
    this.createDocumentScanner = _defaultDocumentScanner,
    this.createEdgeDetector = _defaultEdgeDetector,
    this.createGalleryPicker = _defaultGalleryPicker,
  });
}
