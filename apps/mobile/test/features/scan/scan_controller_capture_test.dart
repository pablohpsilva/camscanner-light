import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_controller.dart';
import 'package:mobile/features/scan/scan_view_state.dart';

import '../../support/fake_scan.dart';

/// Preview controller whose [capture] blocks until [gate] resolves, for
/// deterministic double-tap and dispose-mid-capture tests.
class _GatedCapture implements CameraPreviewController {
  final Completer<void> gate = Completer<void>();
  int captureCount = 0;
  bool disposed = false;

  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<CapturedImage> capture() async {
    captureCount++;
    await gate.future;
    return const CapturedImage('/tmp/gated.jpg');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Preview controller whose [capture] throws a NON-[CameraUnavailableException]
/// (a generic error), to prove capture() degrades gracefully for ANY error type
/// (the binding "no crash" constraint), not just the mapped camera exception.
class _ThrowingCapture implements CameraPreviewController {
  @override
  Future<void> initialize() async {}

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<CapturedImage> capture() async => throw StateError('unexpected boom');

  @override
  Future<void> dispose() async {}
}

Future<ScanController> _ready(CameraPreviewController preview) async {
  final c = ScanController(
    permission: FakeCameraPermissionService(CameraPermissionStatus.granted),
    preview: preview,
  );
  await c.start();
  expect(c.status, ScanStatus.ready);
  return c;
}

void main() {
  test('capture() returns null and stays graceful on an UNEXPECTED error',
      () async {
    final c = await _ready(_ThrowingCapture());
    final image = await c.capture(); // _ThrowingCapture throws a StateError
    expect(image, isNull, reason: 'any error type must degrade to null, no crash');
    expect(c.capturing, isFalse, reason: 'capturing must reset after a throw');
  });

  test('capture() returns the image and toggles capturing on then off',
      () async {
    final fake = FakeCameraPreviewController();
    final c = await _ready(fake);

    final states = <bool>[];
    c.addListener(() => states.add(c.capturing));

    final image = await c.capture();

    expect(image, isNotNull);
    expect(fake.captureCalled, isTrue);
    expect(c.capturing, isFalse);
    expect(states, containsAllInOrder([true, false]));
  });

  test('capture() ignores a second tap while one is in flight', () async {
    final gated = _GatedCapture();
    final c = await _ready(gated);

    final first = c.capture();
    final second = await c.capture(); // in-flight → ignored immediately
    expect(second, isNull);
    expect(gated.captureCount, 1);

    gated.gate.complete();
    expect(await first, isNotNull);
    expect(c.capturing, isFalse);
  });

  test('capture() returns null and does not crash when capture fails', () async {
    final fake = FakeCameraPreviewController()
      ..captureError = const CameraUnavailableException('boom');
    final c = await _ready(fake);

    final image = await c.capture();
    expect(image, isNull);
    expect(c.capturing, isFalse);
  });

  test('capture() returns null when not in the ready state', () async {
    final c = ScanController(
      permission: FakeCameraPermissionService(CameraPermissionStatus.denied),
      preview: FakeCameraPreviewController(),
    );
    await c.start(); // → permissionDenied
    expect(await c.capture(), isNull);
  });

  test('disposing mid-capture does not notify after dispose', () async {
    final gated = _GatedCapture();
    final c = await _ready(gated);

    var notifyCount = 0;
    c.addListener(() => notifyCount++);

    // ignore: unawaited_futures
    c.capture();
    await Future<void>.value(); // progress into capture()'s await

    final countAtDispose = notifyCount;
    c.dispose();
    gated.gate.complete();
    await Future<void>.value();

    expect(notifyCount, equals(countAtDispose),
        reason: 'no notifyListeners() after dispose');
  });
}
