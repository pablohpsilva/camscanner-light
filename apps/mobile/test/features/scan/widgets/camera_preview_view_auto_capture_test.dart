import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/widgets/camera_preview_view.dart';

import '../../../support/fake_scan.dart';

void main() {
  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('auto-capture toggle is present and invokes the callback',
      (tester) async {
    var toggled = false;
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      onAutoCaptureToggled: () => toggled = true,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-auto-capture-toggle')));
    await tester.pump();
    expect(toggled, isTrue);
  });

  testWidgets('toggle icon reflects enabled vs disabled', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
    )));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('scan-auto-capture-toggle')),
          matching: find.byType(Icon),
        )).icon,
        Icons.motion_photos_auto);

    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: false,
    )));
    await tester.pumpAndSettle();
    expect(
        tester.widget<Icon>(find.descendant(
          of: find.byKey(const Key('scan-auto-capture-toggle')),
          matching: find.byType(Icon),
        )).icon,
        Icons.motion_photos_paused);
  });

  testWidgets('ring shows when enabled with progress > 0', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      autoCaptureProgress: 0.5,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsOneWidget);
  });

  testWidgets('ring hidden when progress is 0', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: true,
      autoCaptureProgress: 0.0,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsNothing);
  });

  testWidgets('ring hidden when disabled even with progress', (tester) async {
    await tester.pumpWidget(host(CameraPreviewView(
      controller: FakeCameraPreviewController(),
      onShutter: () {},
      autoCaptureEnabled: false,
      autoCaptureProgress: 0.8,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan-auto-capture-ring')), findsNothing);
  });
}
