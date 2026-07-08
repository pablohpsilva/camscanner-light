import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/document_scanner_service.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/gallery_picker.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

/// A minimal valid 1×1 JPEG (SOI … EOI). The fake writes this so the review
/// screen renders a real, decodable image in tests without camera hardware.
final Uint8List kFakeJpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
  'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
  'AAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q==',
);

/// In-memory fake of [GalleryPicker].
/// - [cancel] true  => pick() returns null (user cancelled).
/// - [throwOnPick]  => pick() throws (platform-error path).
/// - [returnPath]   => pick() returns that exact path. HOST WIDGET TESTS pass a
///   NON-LOADABLE path (e.g. '/nonexistent/import.jpg') so the review screen's
///   FilterPickerStrip does not try to generate thumbnails (which deadlocks under
///   FakeAsync). When null, a real temp file (kFakeJpegBytes) is written — used
///   by the on-device BDD where a loadable file is needed.
class FakeGalleryPicker implements GalleryPicker {
  final bool cancel;
  final bool throwOnPick;
  final String? returnPath;
  const FakeGalleryPicker({
    this.cancel = false,
    this.throwOnPick = false,
    this.returnPath,
  });
  @override
  Future<CapturedImage?> pick() async {
    if (throwOnPick) throw Exception('fake: gallery pick failed');
    if (cancel) return null;
    final path = returnPath;
    if (path != null) return CapturedImage(path);
    final dir = await Directory.systemTemp.createTemp('fake_gallery');
    final file = File('${dir.path}/import.jpg')
      ..writeAsBytesSync(kFakeJpegBytes);
    return CapturedImage(file.path);
  }
}

/// Returns [ScanDependencies] wired with an empty [FakeDocumentScannerService]
/// and a [FakeGalleryPicker]. Used by surviving launch steps and widget tests
/// that need the Home import/scan entry points wired without hardware.
ScanDependencies grantedScanDependencies() => ScanDependencies(
      createGalleryPicker: () => const FakeGalleryPicker(),
      createDocumentScanner: () => FakeDocumentScannerService(const []),
    );

/// Fake [EdgeDetector] for host tests. Returns a fixed [DetectionResult] or
/// null; counts calls.
class FakeEdgeDetector implements EdgeDetector {
  final DetectionResult? result;
  int calls = 0;
  FakeEdgeDetector({this.result});

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    calls++;
    return result;
  }
}

/// A [DocumentScannerService] whose [scan] never completes — use in host widget
/// tests that need to assert "ScanScreen is visible" without letting [_run()]
/// immediately pop back. Unlike [FakeDocumentScannerService([])] (which pops
/// on the same frame), this leaves ScanScreen on-screen indefinitely, allowing
/// assertions before the CircularProgressIndicator causes pumpAndSettle to hang.
class HangingDocumentScannerService implements DocumentScannerService {
  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) =>
      Completer<List<CapturedImage>>().future;
}

/// In-memory fake of [DocumentScannerService]. Returns [pages] (use NON-LOADABLE
/// paths in host widget tests so FilterPickerStrip does not generate thumbnails).
/// An empty [pages] simulates a cancelled scan.
class FakeDocumentScannerService implements DocumentScannerService {
  final List<CapturedImage> pages;
  int scanCalls = 0;
  int? lastPageLimit;
  FakeDocumentScannerService(this.pages);

  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) async {
    scanCalls++;
    lastPageLimit = pageLimit;
    return pages;
  }
}

/// Fake [DocumentScannerService] that returns a different result per call — the
/// i-th `scan()` returns `results[i]` (empty once exhausted). Use for the 2-step
/// ID flow (front call, back call).
class FakeSequentialDocumentScannerService implements DocumentScannerService {
  final List<List<CapturedImage>> results;
  int calls = 0;
  FakeSequentialDocumentScannerService(this.results);

  @override
  Future<List<CapturedImage>> scan({int? pageLimit}) async {
    final out = calls < results.length ? results[calls] : const <CapturedImage>[];
    calls++;
    return out;
  }
}
