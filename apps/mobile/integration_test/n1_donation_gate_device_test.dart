// apps/mobile/integration_test/n1_donation_gate_device_test.dart
// On-device proof for App Store guideline 3.1.1: donation entry points are
// absent on iOS/iPadOS and present on Android.
//
// Run: flutter test integration_test/n1_donation_gate_device_test.dart -d <device-id>
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('donation entry points match the platform rules', (
    tester,
  ) async {
    app.main();
    await tester.pumpAndSettle();

    final matcher = Platform.isIOS ? findsNothing : findsOneWidget;

    expect(find.byKey(const Key('donation-banner')), matcher);

    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-support')), matcher);
  });
}
