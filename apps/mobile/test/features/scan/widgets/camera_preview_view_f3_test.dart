import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/camera_preview_view.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

import '../../../support/fake_scan.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('no overlay when liveCorners is null', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsNothing);
    expect(find.byKey(const Key('live-quad-overlay')), findsNothing);
  });

  testWidgets('overlay appears when liveCorners and previewSize are set',
      (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      liveCorners: CropCorners.fullFrame,
      previewSize: const Size(1920, 1080),
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsOneWidget);
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });

  testWidgets('shutter button is tappable when overlay is shown',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () => tapped = true,
      liveCorners: CropCorners.fullFrame,
      previewSize: const Size(1920, 1080),
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('overlay absent when only liveCorners set (no previewSize)',
      (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      liveCorners: CropCorners.fullFrame,
    )));
    await tester.pumpAndSettle();
    expect(find.byType(LiveQuadOverlay), findsNothing);
  });
}
