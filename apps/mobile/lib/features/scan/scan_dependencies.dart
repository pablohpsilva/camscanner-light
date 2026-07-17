import '../../core/logging/app_logger.dart';
import 'cunning_document_scanner_service.dart';
import 'document_scanner_service.dart';
import 'edge_detector.dart';
import 'opencv_edge_detector.dart';

typedef DocumentScannerServiceFactory = DocumentScannerService Function();
typedef EdgeDetectorFactory = EdgeDetector Function();

DocumentScannerService _defaultDocumentScanner() =>
    const CunningDocumentScannerService();

EdgeDetector _defaultEdgeDetector() => const OpenCvEdgeDetector();

AppLogger _defaultLogger() => const PrintAppLogger();

/// Composition root for the Scan feature. Production uses the defaults; tests
/// inject fakes. Const-constructible so it can be a default widget argument.
///
/// The gallery picker moved to [LibraryDependencies] (P14 task 4): importing a
/// photo into the library is a library concern, not part of the scan flow.
class ScanDependencies {
  final DocumentScannerServiceFactory createDocumentScanner;
  final EdgeDetectorFactory createEdgeDetector;
  final AppLogger Function() logger;

  const ScanDependencies({
    this.createDocumentScanner = _defaultDocumentScanner,
    this.createEdgeDetector = _defaultEdgeDetector,
    this.logger = _defaultLogger,
  });
}
