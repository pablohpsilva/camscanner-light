import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I go back to home from the page viewer
///
/// Pops the page viewer via [EditorTopBar]'s back button. NOTE the key differs
/// from the settings screens: those use [AppBackHeader]'s `Key('back')` (see
/// `i_navigate_back_to_home`), while the page viewer has its own dark editor
/// chrome keyed `page-viewer-back`. Using the wrong one fails with
/// "Found 0 widgets with key [<'back'>]".
///
/// Needed before an in-test relaunch: a second `runCamScannerApp` pumps into
/// the EXISTING element tree, so the Navigator keeps its route stack and the
/// relaunched UI only shows home if home is already the top route.
Future<void> iGoBackToHomeFromThePageViewer(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-back')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('home-settings')), findsOneWidget);
}
