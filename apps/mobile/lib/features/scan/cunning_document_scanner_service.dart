import 'package:cunning_document_scanner/cunning_document_scanner.dart';

import 'captured_image.dart';
import 'document_scanner_service.dart';

/// Injectable launcher seam so normalization is testable without the plugin.
typedef ScannerLauncher = Future<List<String>?> Function({int? noOfPages});

/// Default launcher: the real plugin call. `noOfPages` null → a high cap
/// (effectively "no practical limit"); camera source only (gallery import
/// stays on the existing image_picker path).
Future<List<String>?> _pluginLaunch({int? noOfPages}) =>
    CunningDocumentScanner.getPictures(
      noOfPages: noOfPages ?? 100,
      scannerSource: ScannerSource.camera,
    );

class CunningDocumentScannerService implements DocumentScannerService {
  final ScannerLauncher launch;
  const CunningDocumentScannerService({this.launch = _pluginLaunch});

  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) async {
    try {
      final paths = await launch(noOfPages: pageLimit);
      if (paths == null) return const [];
      return paths.map(CapturedImage.new).toList();
    } catch (_) {
      return const [];
    }
  }
}
