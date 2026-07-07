import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/document_scanner_service.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/gallery_picker.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_flash_mode.dart';

/// A minimal valid 1×1 JPEG (SOI … EOI). The fake writes this so the review
/// screen renders a real, decodable image in tests without camera hardware.
final Uint8List kFakeJpegBytes = base64Decode(
  '/9j/4AAQSkZJRgABAQEAYABgAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRof'
  'Hh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/wAALCAABAAEBAREA/8QAFAAB'
  'AAAAAAAAAAAAAAAAAAAAA//EABQQAQAAAAAAAAAAAAAAAAAAAAD/2gAIAQEAAD8AfwD/2Q==',
);

/// In-memory fake of [CameraPermissionService] — returns a fixed status.
class FakeCameraPermissionService implements CameraPermissionService {
  final CameraPermissionStatus status;
  bool openSettingsCalled = false;

  FakeCameraPermissionService(this.status);

  @override
  Future<CameraPermissionStatus> request() async => status;

  @override
  Future<bool> openSettings() async {
    openSettingsCalled = true;
    return true;
  }
}

/// Fake [CameraPreviewController] that paints a deterministic placeholder
/// instead of real camera frames, so on-device tests need no hardware.
class FakeCameraPreviewController implements CameraPreviewController {
  final bool unavailable;
  final String? captureReturnPath;
  bool disposed = false;
  bool captureCalled = false;
  CameraUnavailableException? captureError;

  bool sampling = false;
  ScanFlashMode? lastFlashMode;
  void Function(CameraFrame)? _onFrame;

  FakeCameraPreviewController({
    this.unavailable = false,
    this.captureReturnPath,
  });

  @override
  Future<void> initialize() async {
    if (unavailable) {
      throw const CameraUnavailableException('fake: no camera');
    }
  }

  @override
  Widget buildPreview() => const ColoredBox(
        color: Colors.black,
        child: Center(
          child: Text('FAKE PREVIEW', key: Key('fake-preview')),
        ),
      );

  @override
  Future<CapturedImage> capture() async {
    captureCalled = true;
    final err = captureError;
    if (err != null) throw err;
    final override = captureReturnPath;
    if (override != null) return CapturedImage(override); // no file written
    final dir = await Directory.systemTemp.createTemp('fake_capture');
    final file = File('${dir.path}/page.jpg');
    await file.writeAsBytes(kFakeJpegBytes);
    return CapturedImage(file.path);
  }

  @override
  void startSampling(void Function(CameraFrame frame) onFrame) {
    sampling = true;
    _onFrame = onFrame;
  }

  @override
  void stopSampling() {
    sampling = false;
    _onFrame = null;
  }

  /// Test hook: simulate a streamed frame.
  void emitFrame(CameraFrame frame) {
    if (sampling) _onFrame?.call(frame);
  }

  @override
  Future<void> setFlashMode(ScanFlashMode mode) async {
    lastFlashMode = mode;
  }

  @override
  Size get previewSize => const Size(1920, 1080);

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

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

/// Returns [ScanDependencies] wired with a [FakeCameraPermissionService] that
/// reports [CameraPermissionStatus.granted] and an always-available
/// [FakeCameraPreviewController].
ScanDependencies grantedScanDependencies() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: FakeCameraPreviewController.new,
      createGalleryPicker: () => const FakeGalleryPicker(),
    );

/// Returns [ScanDependencies] wired with a [FakeCameraPermissionService] that
/// reports [CameraPermissionStatus.denied] (or [CameraPermissionStatus.permanentlyDenied]
/// when [permanently] is `true`).
ScanDependencies deniedScanDependencies({bool permanently = false}) =>
    ScanDependencies(
      createPermissionService: () => FakeCameraPermissionService(
        permanently
            ? CameraPermissionStatus.permanentlyDenied
            : CameraPermissionStatus.denied,
      ),
      createPreviewController: FakeCameraPreviewController.new,
    );

/// Returns [ScanDependencies] wired with a [FakeCameraPermissionService] that
/// reports [CameraPermissionStatus.granted] and a [FakeCameraPreviewController]
/// that throws [CameraUnavailableException] on [initialize].
ScanDependencies unavailableScanDependencies() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () =>
          FakeCameraPreviewController(unavailable: true),
    );

/// Fake [EdgeDetector] for host tests. Returns a fixed [DetectionResult] or
/// null; counts calls.
class FakeEdgeDetector implements EdgeDetector {
  final DetectionResult? result;
  int calls = 0;
  int frameCalls = 0;
  FakeEdgeDetector({this.result});

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    calls++;
    return result;
  }

  @override
  Future<DetectionResult?> detectFrame(CameraFrame frame) async {
    frameCalls++;
    return result;
  }
}

/// Returns [ScanDependencies] wired with a [FakeEdgeDetector] that returns
/// [result], plus a granted [FakeCameraPermissionService] and an always-available
/// [FakeCameraPreviewController] that writes [kFakeJpegBytes] to a temp file.
/// Use this in BDD step definitions that need controllable edge detection.
ScanDependencies grantedScanDependenciesWithDetector(DetectionResult? result) =>
    ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: FakeCameraPreviewController.new,
      createEdgeDetector: () => FakeEdgeDetector(result: result),
    );

/// Module-level handle to the [FakeCameraPreviewController] most recently
/// created by [liveDetectionScanDependencies]. Step definitions use this to
/// emit frames without needing a return value from the factory.
FakeCameraPreviewController? liveDetectionFakePreview;

/// [ScanDependencies] with controllable frame sampling and edge detection.
/// Use in F3 widget and BDD tests. The preview controller delivers frames via
/// the image-stream API ([startSampling]/[stopSampling]/[detectFrame]);
/// the edge detector returns [detectionResult] from [detectFrame()].
ScanDependencies liveDetectionScanDependencies({
  required DetectionResult? detectionResult,
}) =>
    ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () {
        final c = FakeCameraPreviewController();
        liveDetectionFakePreview = c;
        return c;
      },
      createEdgeDetector: () => FakeEdgeDetector(result: detectionResult),
    );

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
