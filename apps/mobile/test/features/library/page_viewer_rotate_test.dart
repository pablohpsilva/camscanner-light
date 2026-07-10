import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Rotate invokes rotatePage for the current page', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-rotate')));
    await tester.pumpAndSettle();

    expect(repo.rotateCalls, 1);
    expect(repo.lastRotatedPosition, 1);
  });
}
