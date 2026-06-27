import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/scan_controller.dart';
import 'package:mobile/features/scan/scan_view_state.dart';

import '../../support/fake_scan.dart';

void main() {
  group('ScanController.start()', () {
    test('granted + camera available → ready', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.ready);
      expect(c.permanentlyDenied, isFalse);
    });

    test('granted but no camera → unavailable', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(unavailable: true),
      );
      await c.start();
      expect(c.status, ScanStatus.unavailable);
    });

    test('denied → permissionDenied, not permanent', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.denied),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.permissionDenied);
      expect(c.permanentlyDenied, isFalse);
    });

    test('permanentlyDenied → permissionDenied, permanent flag set', () async {
      final c = ScanController(
        permission:
            FakeCameraPermissionService(CameraPermissionStatus.permanentlyDenied),
        preview: FakeCameraPreviewController(),
      );
      await c.start();
      expect(c.status, ScanStatus.permissionDenied);
      expect(c.permanentlyDenied, isTrue);
    });

    test('notifies listeners on transition', () async {
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: FakeCameraPreviewController(),
      );
      var notifications = 0;
      c.addListener(() => notifications++);
      await c.start();
      expect(notifications, greaterThan(0));
    });

    test('openSettings() delegates to the permission service', () async {
      final perm = FakeCameraPermissionService(CameraPermissionStatus.denied);
      final c = ScanController(permission: perm, preview: FakeCameraPreviewController());
      final opened = await c.openSettings();
      expect(opened, isTrue);
      expect(perm.openSettingsCalled, isTrue);
    });
  });
}
