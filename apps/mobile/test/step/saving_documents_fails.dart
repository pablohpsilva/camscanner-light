import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: saving documents fails
Future<void> savingDocumentsFails(WidgetTester tester) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: failingLibraryDependencies(),
  );
  await tester.pumpAndSettle();
}
