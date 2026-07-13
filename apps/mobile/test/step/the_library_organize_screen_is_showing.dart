import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/organize_actions_bdd_state.dart';

/// Usage: the library organize screen is showing
///
/// Pumps [HomeScreen] against the [FakeDocumentRepository] built up by any
/// earlier "the library has a document ..." seed steps in this scenario.
/// Named distinctly from "the library home screen is showing" (the
/// folder/tag filter scenarios' step) even though it pumps the same screen,
/// so this scenario's steps stay scoped to their own shared BDD state
/// ([bddOrganizeRepo]) rather than accidentally reusing folder_filter's.
Future<void> theLibraryOrganizeScreenIsShowing(WidgetTester tester) async {
  final repo = bddOrganizeRepo ??= FakeDocumentRepository();
  addTearDown(resetOrganizeActionsBddState);

  await tester.pumpWidget(
    MaterialApp(
      theme: ReamTheme.light(),
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
