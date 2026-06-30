import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/edge_detector.dart';

import '../../support/fake_scan.dart';

void main() {
  group('FakeCameraPreviewController.sampleFrame', () {
    test('returns sampleFrameResult when set', () async {
      final controller = FakeCameraPreviewController(
        sampleFrameResult: Uint8List.fromList([1, 2, 3]),
      );
      final result = await controller.sampleFrame();
      expect(result, equals(Uint8List.fromList([1, 2, 3])));
      expect(controller.sampleFrameCalls, 1);
    });

    test('returns null when sampleFrameResult is null', () async {
      final controller = FakeCameraPreviewController();
      final result = await controller.sampleFrame();
      expect(result, isNull);
      expect(controller.sampleFrameCalls, 1);
    });

    test('increments sampleFrameCalls on each call', () async {
      final controller = FakeCameraPreviewController();
      await controller.sampleFrame();
      await controller.sampleFrame();
      expect(controller.sampleFrameCalls, 2);
    });
  });

  group('FakeCameraPreviewController.previewSize', () {
    test('returns 1920x1080', () {
      final controller = FakeCameraPreviewController();
      expect(controller.previewSize, const Size(1920, 1080));
    });
  });

  group('liveDetectionScanDependencies', () {
    const confidentResult = DetectionResult(
      corners: CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      ),
      confidence: 0.8,
    );

    test('edge detector returns configured result', () async {
      final deps = liveDetectionScanDependencies(
          detectionResult: confidentResult);
      final detector = deps.createEdgeDetector();
      final result = await detector.detect(Uint8List.fromList([0]));
      expect(result, confidentResult);
    });

    test('edge detector returns null when configured as null', () async {
      final deps =
          liveDetectionScanDependencies(detectionResult: null);
      final detector = deps.createEdgeDetector();
      final result = await detector.detect(Uint8List.fromList([0]));
      expect(result, isNull);
    });

    test('preview controller sampleFrame returns kFakeJpegBytes by default',
        () async {
      final deps =
          liveDetectionScanDependencies(detectionResult: null);
      final controller = deps.createPreviewController()
          as FakeCameraPreviewController;
      final bytes = await controller.sampleFrame();
      expect(bytes, kFakeJpegBytes);
    });
  });
}
