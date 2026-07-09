import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/cunning_document_scanner_service.dart';
import 'package:mobile/features/scan/gallery_picker.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';
import 'package:mobile/features/scan/photo_camera.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

void main() {
  test(
    'production ScanDependencies wires the plugin-backed implementations',
    () {
      const deps = ScanDependencies();
      expect(deps.createGalleryPicker(), isA<ImagePickerGalleryPicker>());
    },
  );

  test('createEdgeDetector() returns OpenCvEdgeDetector', () {
    expect(
      const ScanDependencies().createEdgeDetector(),
      isA<OpenCvEdgeDetector>(),
    );
  });

  test('createDocumentScanner defaults to CunningDocumentScannerService', () {
    const deps = ScanDependencies();
    expect(deps.createDocumentScanner(), isA<CunningDocumentScannerService>());
  });

  test('createPhotoCamera defaults to ImagePickerPhotoCamera', () {
    expect(
      const ScanDependencies().createPhotoCamera(),
      isA<ImagePickerPhotoCamera>(),
    );
  });
}
