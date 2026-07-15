import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/main.dart' as app;
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the app is launched with empty storage and mocked preferences
///
/// `runCamScannerApp` mounts via bare `runApp()`, which flutter_test does NOT
/// auto-detach between `testWidgets` blocks (only `tester.pumpWidget` trees
/// participate in that lifecycle). In a multi-scenario file, a still-live
/// tree from the previous scenario would otherwise race this scenario's own
/// DB/tickers. Tear it down first — safe as a no-op on the very first
/// scenario too.
Future<void> theAppIsLaunchedWithEmptyStorageAndMockedPreferences(
  WidgetTester tester,
) async {
  await tester.pumpWidget(const SizedBox());
  SharedPreferences.setMockInitialValues(const {});
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
