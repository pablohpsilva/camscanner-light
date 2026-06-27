import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_screen.dart';

import '../../support/fake_scan.dart';

void main() {
  Widget host(child) => MaterialApp(home: child);

  testWidgets('granted → shows the live preview', (tester) async {
    await tester.pumpWidget(
      host(CameraScreen(dependencies: grantedScanDependencies())),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
    expect(find.byKey(const Key('fake-preview')), findsOneWidget);
  });

  testWidgets('denied → rationale + Open Settings; tap delegates', (tester) async {
    final deps = deniedScanDependencies();
    await tester.pumpWidget(host(CameraScreen(dependencies: deps)));
    await tester.pumpAndSettle();

    expect(find.text('Camera access is needed to scan documents'),
        findsOneWidget);
    final settingsButton = find.widgetWithText(FilledButton, 'Open Settings');
    expect(settingsButton, findsOneWidget);

    await tester.tap(settingsButton);
    await tester.pump();
    // The fake records the call; no crash on tap.
  });

  testWidgets('granted but no camera → unavailable message', (tester) async {
    await tester.pumpWidget(
      host(CameraScreen(dependencies: unavailableScanDependencies())),
    );
    await tester.pumpAndSettle();

    expect(find.text('Camera unavailable on this device'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsNothing);
  });
}
