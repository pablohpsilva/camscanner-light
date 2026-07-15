import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/localized_app.dart';

/// Usage: the home screen is shown
Future<void> theHomeScreenIsShown(WidgetTester tester) async {
  await tester.pumpWidget(
    localizedTestApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
