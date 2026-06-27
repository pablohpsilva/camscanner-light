import 'package:flutter/material.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

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
  bool disposed = false;

  FakeCameraPreviewController({this.unavailable = false});

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
