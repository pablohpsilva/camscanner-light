import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  Document makeDoc(int id, String name) => Document(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 7, 1),
    modifiedAt: DateTime.utc(2026, 7, 1),
  );

  testWidgets('Merge lists other documents and merges the chosen one', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      documents: [makeDoc(1, 'Alpha'), makeDoc(2, 'Beta')],
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 1, name: 'Alpha', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-merge')));
    await tester.pumpAndSettle();

    // Dialog shows the OTHER document, not the current one.
    expect(find.byKey(const Key('merge-picker-dialog')), findsOneWidget);
    // "Beta" appears inside the dialog (the other doc).
    expect(
      find.descendant(
        of: find.byKey(const Key('merge-picker-dialog')),
        matching: find.text('Beta'),
      ),
      findsOneWidget,
    );
    // "Alpha" must NOT appear inside the dialog (current doc is filtered out).
    expect(
      find.descendant(
        of: find.byKey(const Key('merge-picker-dialog')),
        matching: find.text('Alpha'),
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('merge-picker-item-2')));
    await tester.pumpAndSettle();

    expect(repo.lastMergeTarget, 1);
    expect(repo.lastMergeSource, 2);
  });

  testWidgets(
    'Merge shows an empty message when there are no other documents',
    (tester) async {
      final repo = FakeDocumentRepository(
        documents: [makeDoc(1, 'Only')],
        pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
      );
      await tester.pumpWidget(
        localizedTestApp(
          home: PageViewerScreen(documentId: 1, name: 'Only', repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-merge')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('merge-picker-empty')), findsOneWidget);
    },
  );
}
