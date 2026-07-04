import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';

import '../support/fake_scan.dart';

/// Usage: the live overlay sample timer fires
/// (Now stream-based: emits one preview frame through the fake so the
/// screen's _onFrame runs detectFrame — the 800ms Timer was removed.)
Future<void> theLiveOverlaySampleTimerFires(WidgetTester tester) async {
  final fake = liveDetectionFakePreview;
  expect(fake, isNotNull,
      reason: 'liveDetectionScanDependencies must have built the fake preview');
  expect(fake!.sampling, isTrue,
      reason: 'sampling should be active once camera is ready');
  fake.emitFrame(CameraFrame(
    width: 2,
    height: 2,
    format: CameraFrameFormat.bgra8888,
    planes: [
      CameraFramePlane(
        bytes: Uint8List(2 * 2 * 4),
        bytesPerRow: 8,
        bytesPerPixel: 4,
      )
    ],
  ));
  await tester.pump(); // detectFrame future
  await tester.pump(); // setState → overlay rebuild
}
