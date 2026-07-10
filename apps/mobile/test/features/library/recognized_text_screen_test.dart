import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Widget host(FakeDocumentRepository repo, {String? initialText}) =>
      MaterialApp(
        home: RecognizedTextScreen(
          documentId: 1,
          position: 1,
          name: 'My Report',
          initialText: initialText,
          repository: repo,
        ),
      );

  testWidgets('renders the page text as selectable text', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD'),
      ],
    );
    await tester.pumpWidget(host(repo, initialText: 'HELLO WORLD'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
    expect(find.text('HELLO WORLD'), findsWidgets);
  });

  testWidgets('Copy places the text on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD'),
      ],
    );
    await tester.pumpWidget(host(repo, initialText: 'HELLO WORLD'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('recognized-text-copy')));
    await tester.pumpAndSettle();

    expect(copied, 'HELLO WORLD');
    expect(find.text('Copied'), findsOneWidget);
  });

  testWidgets(
    'empty page offers Recognize text; tapping runs OCR and shows result',
    (tester) async {
      final repo = FakeDocumentRepository(
        // Page starts with NO text → empty state; runOcr "recognizes" the text.
        pages: const [PageImage(position: 1, imagePath: '/x.jpg')],
        recognizesText: 'RECOGNIZED NOW',
      );
      await tester.pumpWidget(host(repo, initialText: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recognized-text-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('recognized-text-run')));
      await tester.pumpAndSettle();

      expect(repo.ranOcr, isTrue);
      expect(find.byKey(const Key('recognized-text-body')), findsOneWidget);
      expect(find.text('RECOGNIZED NOW'), findsWidgets);
    },
  );
}
