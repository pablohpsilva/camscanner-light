import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/scan_controller.dart';
import 'package:mobile/features/scan/scan_view_state.dart';

import '../../support/fake_scan.dart';

/// A [CameraPreviewController] whose [initialize] only completes when the
/// [gate] completer is resolved, enabling deterministic mid-start dispose tests.
class _GatedPreviewController implements CameraPreviewController {
  final Completer<void> gate = Completer<void>();
  bool initialized = false;
  bool disposed = false;

  @override
  Future<void> initialize() async {
    await gate.future;
    initialized = true;
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

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
      expect(notifications, 2);
    });

    test('openSettings() delegates to the permission service', () async {
      final perm = FakeCameraPermissionService(CameraPermissionStatus.denied);
      final c = ScanController(permission: perm, preview: FakeCameraPreviewController());
      final opened = await c.openSettings();
      expect(opened, isTrue);
      expect(perm.openSettingsCalled, isTrue);
    });

    test(
        'disposing mid-start does not notify after dispose and releases a late-initialized camera',
        () async {
      final gated = _GatedPreviewController();
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
        preview: gated,
      );

      var notifyCount = 0;
      c.addListener(() => notifyCount++);

      // Launch start() without awaiting — it will stall at initialize().
      // ignore: unawaited_futures
      c.start();

      // Pump a microtask so start() progresses past the permission await and
      // reaches the initialize() await inside the gated controller.
      await Future<void>.value();

      // Capture notification count at the moment of disposal.
      final countAtDispose = notifyCount;

      // Dispose the controller while initialize() is still in flight.
      c.dispose();

      // Unblock initialize() — simulates the camera finishing init after dispose.
      gated.gate.complete();
      await Future<void>.value();

      // Status must not have advanced to ready (the post-dispose guard fired).
      expect(c.status, isNot(ScanStatus.ready));

      // The late-initialized camera must have been released to avoid a native leak.
      expect(gated.disposed, isTrue);

      // No additional notifications must have fired after disposal.
      expect(notifyCount, equals(countAtDispose),
          reason: 'notifyListeners() must not be called on a disposed ChangeNotifier');
    });

    test('dispose() delegates to preview.dispose()', () async {
      final preview = FakeCameraPreviewController();
      final c = ScanController(
        permission: FakeCameraPermissionService(CameraPermissionStatus.denied),
        preview: preview,
      );
      c.dispose();
      expect(preview.disposed, isTrue);
    });
  });
}
