import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, FakeDocumentRepository repo) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoDocs() {
    final t = DateTime.utc(2026, 7, 1, 12);
    return FakeDocumentRepository(documents: [
      Document(id: 1, name: 'Invoice March', createdAt: t, modifiedAt: t),
      Document(id: 2, name: 'Grocery list', createdAt: t, modifiedAt: t),
    ]);
  }

  testWidgets('search filters the list to matching documents', (tester) async {
    await pumpHome(tester, twoDocs());
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsOneWidget);

    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-field')), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'invoice');
    await tester.pumpAndSettle();
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsNothing);
  });

  testWidgets('clear restores the full list', (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'invoice');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('documents-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('Invoice March'), findsOneWidget);
    expect(find.text('Grocery list'), findsOneWidget);
  });

  testWidgets('a query with no matches shows the empty-search state',
      (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('documents-search-field')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-empty')), findsOneWidget);
  });

  testWidgets('close exits search mode and restores the sort bar',
      (tester) async {
    await pumpHome(tester, twoDocs());
    await tester.tap(find.byKey(const Key('documents-search')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sort-control-bar')), findsNothing);

    await tester.tap(find.byKey(const Key('documents-search-close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('documents-search-field')), findsNothing);
    expect(find.byKey(const Key('sort-control-bar')), findsOneWidget);
  });
}
