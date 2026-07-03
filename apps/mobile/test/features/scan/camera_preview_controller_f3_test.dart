import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_frame.dart';
import 'package:mobile/features/scan/scan_flash_mode.dart';
import '../../support/fake_scan.dart';

CameraFrame _frame() => CameraFrame(
      width: 2,
      height: 2,
      format: CameraFrameFormat.bgra8888,
      planes: [
        CameraFramePlane(
            bytes: Uint8List(2 * 2 * 4), bytesPerRow: 8, bytesPerPixel: 4),
      ],
    );

void main() {
  test('startSampling registers a callback that emitFrame invokes', () {
    final c = FakeCameraPreviewController();
    final received = <CameraFrame>[];
    c.startSampling(received.add);
    expect(c.sampling, isTrue);
    c.emitFrame(_frame());
    c.emitFrame(_frame());
    expect(received, hasLength(2));
  });

  test('stopSampling halts delivery', () {
    final c = FakeCameraPreviewController();
    final received = <CameraFrame>[];
    c.startSampling(received.add);
    c.stopSampling();
    expect(c.sampling, isFalse);
    c.emitFrame(_frame());
    expect(received, isEmpty);
  });

  test('setFlashMode records the requested mode', () async {
    final c = FakeCameraPreviewController();
    await c.setFlashMode(ScanFlashMode.torch);
    expect(c.lastFlashMode, ScanFlashMode.torch);
  });

  test('previewSize returns 1920x1080', () {
    expect(FakeCameraPreviewController().previewSize, const Size(1920, 1080));
  });
}
