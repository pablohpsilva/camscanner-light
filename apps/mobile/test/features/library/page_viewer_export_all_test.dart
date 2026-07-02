import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Export all as images shows a confirmation with the count',
      (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump(); // let the async export + snackbar schedule
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Exported 2 images'), findsOneWidget);
  });

  testWidgets('a failing export shows an error snackbar', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExportImage: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text("Couldn't export images"), findsOneWidget);
  });
}
