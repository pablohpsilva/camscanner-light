import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the app relaunches reading the same preferences
///
/// Deliberately does NOT call `SharedPreferences.setMockInitialValues` —
/// the mock prefs persist within the test process, so this proves the
/// language choice saved by a previous step is read back on relaunch.
Future<void> theAppRelaunchesReadingTheSamePreferences(
  WidgetTester tester,
) async {
  await tester.pumpWidget(const SizedBox());
  final store = SharedPrefsLocaleStore();
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: tempLibraryDependencies(),
    localeController: LocaleController(
      store: store,
      initial: await store.load(),
    ),
  );
  await tester.pumpAndSettle();
}
