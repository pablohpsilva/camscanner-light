import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/folder_filter_bdd_state.dart';

/// Usage: the library home screen is showing
///
/// Pumps [HomeScreen] against the [FakeDocumentRepository] built up by any
/// earlier "the library has a document ..." seed steps in this scenario.
Future<void> theLibraryHomeScreenIsShowing(WidgetTester tester) async {
  final repo = bddFolderRepo ??= FakeDocumentRepository();
  addTearDown(resetFolderFilterBddState);

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
