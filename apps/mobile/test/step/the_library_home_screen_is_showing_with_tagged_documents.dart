import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/tag_filter_bdd_state.dart';

/// Usage: the library home screen is showing with tagged documents
///
/// Pumps [HomeScreen] against the [FakeDocumentRepository] built up by any
/// earlier "the library has a document ... tagged/with no tags" seed steps in
/// this scenario. Named distinctly from
/// the_library_home_screen_is_showing.dart (the folder-filter variant)
/// because bdd_widget_test keys generated steps by exact sentence text, and
/// this scenario must pump against [bddTagRepo] rather than [bddFolderRepo].
Future<void> theLibraryHomeScreenIsShowingWithTaggedDocuments(
  WidgetTester tester,
) async {
  final repo = bddTagRepo ??= FakeDocumentRepository();
  addTearDown(resetTagFilterBddState);

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
