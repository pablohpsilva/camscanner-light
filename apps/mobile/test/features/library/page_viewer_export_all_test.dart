import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('Share all as images shares one JPG per page', (tester) async {
    final repo = FakeDocumentRepository(pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 1, name: 'Doc', repository: repo, share: share),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 1);
    expect(share.lastFilePaths!.length, 2);
    expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
    expect(share.lastSubject, 'Doc');
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExportImage: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 1, name: 'Doc', repository: repo, share: share),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-all-images')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share images"), findsOneWidget);
  });
}
