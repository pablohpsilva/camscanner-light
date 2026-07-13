import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: the app launches with the print feature disabled
Future<void> theAppLaunchesWithThePrintFeatureDisabled(
  WidgetTester tester,
) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: persistentLibraryDependencies(
      dbFile: persistentDbFile!,
      baseDir: persistentDir!,
      features: const FeatureFlags(print: false),
    ),
  );
  await tester.pumpAndSettle();
}
