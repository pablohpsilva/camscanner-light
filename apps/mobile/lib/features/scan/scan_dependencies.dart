import 'cunning_document_scanner_service.dart';
import 'document_scanner_service.dart';
import 'edge_detector.dart';
import 'gallery_picker.dart';
import 'opencv_edge_detector.dart';
import 'photo_camera.dart';

typedef DocumentScannerServiceFactory = DocumentScannerService Function();
typedef EdgeDetectorFactory = EdgeDetector Function();
typedef GalleryPickerFactory = GalleryPicker Function();
typedef PhotoCameraFactory = PhotoCamera Function();

DocumentScannerService _defaultDocumentScanner() =>
    const CunningDocumentScannerService();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

GalleryPicker _defaultGalleryPicker() => const ImagePickerGalleryPicker();

PhotoCamera _defaultPhotoCamera() => const ImagePickerPhotoCamera();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
class ScanDependencies {
  final DocumentScannerServiceFactory createDocumentScanner;
  final EdgeDetectorFactory createEdgeDetector;
  final GalleryPickerFactory createGalleryPicker;
  final PhotoCameraFactory createPhotoCamera;

  const ScanDependencies({
    this.createDocumentScanner = _defaultDocumentScanner,
    this.createEdgeDetector = _defaultEdgeDetector,
    this.createGalleryPicker = _defaultGalleryPicker,
    this.createPhotoCamera = _defaultPhotoCamera,
  });
}
