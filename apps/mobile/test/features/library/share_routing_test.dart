import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('PdfPreviewScreen Share routes the PDF through the channel', (
    tester,
  ) async {
    final share = FakeShareChannel();
    await tester.pumpWidget(
      MaterialApp(
        home: PdfPreviewScreen(
          pdfPath: '/docs/report.pdf',
          name: 'Report',
          share: share,
          // opener throws → screen shows the error state, but the Share action in
          // the app bar is always present and independent of load state.
          opener: (_) =>
              Future.error(StateError('no native pdfx in host test')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('pdf-preview-share')),
    ); // opens the menu
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-menu-share')));
    await tester.pump();

    expect(share.calls, 1);
    expect(share.lastFilePaths, ['/docs/report.pdf']);
    expect(share.lastSubject, 'Report');
  });

  testWidgets(
    'RecognizedTextScreen Share routes the .txt through the channel',
    (tester) async {
      final repo = FakeDocumentRepository(
        pages: const [
          PageImage(position: 1, imagePath: '/a.jpg', ocrText: 'HELLO'),
        ],
      );
      final share = FakeShareChannel();
      await tester.pumpWidget(
        MaterialApp(
          home: RecognizedTextScreen(
            documentId: 7,
            position: 1,
            name: 'Notes',
            initialText: 'HELLO',
            repository: repo,
            share: share,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('recognized-text-share')),
      ); // direct-share button; fires _share() on a single tap
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(share.calls, 1);
      expect(share.lastFilePaths, isNotNull);
      expect(share.lastFilePaths!.single, endsWith('.txt'));
      expect(share.lastSubject, 'Notes');
    },
  );

  testWidgets(
    'PageViewer protect flow routes the protected PDF through channel',
    (tester) async {
      final repo = FakeDocumentRepository(
        pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
      );
      final share = FakeShareChannel();
      await tester.pumpWidget(
        MaterialApp(
          home: PageViewerScreen(
            documentId: 5,
            name: 'Doc',
            repository: repo,
            share: share,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('page-viewer-share')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-protect')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('password-field')), 'secret');
      await tester.pump();
      await tester.tap(find.byKey(const Key('password-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(share.calls, 1);
      expect(share.lastFilePaths, isNotNull);
      expect(share.lastFilePaths!.single, endsWith('.pdf'));
      expect(share.lastSubject, 'Doc');
    },
  );
}
