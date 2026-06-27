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

  testWidgets('shows the Documents app bar title', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no documents',
      (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('lists saved documents when storage is non-empty',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('shows a tappable Scan button once loaded', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    final fab = tester.widget<FloatingActionButton>(
      find.widgetWithText(FloatingActionButton, 'Scan'),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('tapping Scan opens the camera screen', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });
}
