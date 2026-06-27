import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_preview_controller.dart';

import '../../support/fake_scan.dart';

void main() {
  test('fake capture() writes a non-empty JPEG file to a temp path', () async {
    final fake = FakeCameraPreviewController();
    final image = await fake.capture();

    final file = File(image.path);
    expect(file.existsSync(), isTrue, reason: 'capture must produce a real file');
    final bytes = await file.readAsBytes();
    expect(bytes.length, greaterThan(2));
    // JPEG SOI marker 0xFFD8 … EOI marker 0xFFD9 (proves real JPEG bytes).
    expect([bytes[0], bytes[1]], [0xFF, 0xD8]);
    expect([bytes[bytes.length - 2], bytes[bytes.length - 1]], [0xFF, 0xD9]);
    expect(fake.captureCalled, isTrue);
  });

  test('fake capture() throws when captureError is set', () async {
    final fake = FakeCameraPreviewController()
      ..captureError = const CameraUnavailableException('fake: capture failed');
    expect(fake.capture(), throwsA(isA<CameraUnavailableException>()));
  });
}
