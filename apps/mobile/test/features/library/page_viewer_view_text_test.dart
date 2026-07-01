import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('View text opens the recognized-text screen for the current page',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD')],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-view-text')));
    await tester.pumpAndSettle();

    // On the recognized-text screen now.
    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.text('HELLO WORLD'), findsWidgets);
  });
}
