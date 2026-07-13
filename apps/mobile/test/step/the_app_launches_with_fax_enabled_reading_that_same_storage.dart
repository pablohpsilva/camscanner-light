import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: the app launches with fax enabled reading that same storage
Future<void> theAppLaunchesWithFaxEnabledReadingThatSameStorage(
  WidgetTester tester,
) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: persistentLibraryDependencies(
      dbFile: persistentDbFile!,
      baseDir: persistentDir!,
      features: const FeatureFlags(fax: true),
    ),
  );
  await tester.pumpAndSettle();
}
