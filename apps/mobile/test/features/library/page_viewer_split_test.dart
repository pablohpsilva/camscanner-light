import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> openMenuAndSplit(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-split')));
    await tester.pumpAndSettle();
  }

  testWidgets('Split after this page splits when not on the last page',
      (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 7, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await openMenuAndSplit(tester);

    expect(repo.lastSplitDoc, 7);
    expect(repo.lastSplitPosition, 1);
    expect(find.text('Split into a new document'), findsOneWidget);
  });

  testWidgets('Split on the only (last) page shows a message and does not split',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 7, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await openMenuAndSplit(tester);

    expect(repo.lastSplitDoc, isNull);
    expect(find.textContaining('last page'), findsOneWidget);
  });
}
