import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

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
  final Uint8List? sampleFrameResult;
  bool disposed = false;
  bool captureCalled = false;
  int sampleFrameCalls = 0;
  CameraUnavailableException? captureError;

  FakeCameraPreviewController({
    this.unavailable = false,
    this.captureReturnPath,
    this.sampleFrameResult,
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
  Future<Uint8List?> sampleFrame() async {
    sampleFrameCalls++;
    return sampleFrameResult;
  }

  @override
  Size get previewSize => const Size(1920, 1080);

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Returns [ScanDependencies] wired with a [FakeCameraPermissionService] that
/// reports [CameraPermissionStatus.granted] and an always-available
/// [FakeCameraPreviewController].
ScanDependencies grantedScanDependencies() => ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: FakeCameraPreviewController.new,
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
  FakeEdgeDetector({this.result});

  @override
  Future<DetectionResult?> detect(Uint8List bytes) async {
    calls++;
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

/// [ScanDependencies] with controllable frame sampling and edge detection.
/// Use in F3 widget and BDD tests. The preview controller returns
/// [sampleFrameResult] (defaults to [kFakeJpegBytes]) from [sampleFrame()];
/// the edge detector returns [detectionResult] from [detect()].
ScanDependencies liveDetectionScanDependencies({
  required DetectionResult? detectionResult,
  Uint8List? sampleFrameResult,
}) =>
    ScanDependencies(
      createPermissionService: () =>
          FakeCameraPermissionService(CameraPermissionStatus.granted),
      createPreviewController: () => FakeCameraPreviewController(
        sampleFrameResult: sampleFrameResult ?? kFakeJpegBytes,
      ),
      createEdgeDetector: () => FakeEdgeDetector(result: detectionResult),
    );
