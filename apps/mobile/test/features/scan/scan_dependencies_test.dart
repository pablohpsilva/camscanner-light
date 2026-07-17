import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/cunning_document_scanner_service.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

void main() {
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
}
