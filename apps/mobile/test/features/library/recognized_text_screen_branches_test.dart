// Branch coverage for RecognizedTextScreen: the runOcr-failure SnackBar (lines
// 78-81), the export/share-failure SnackBar (lines 105-108), and the back
// button's Navigator.maybePop callback (line 121).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/recognized_text_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

class _ThrowingRunOcrRepository extends FakeDocumentRepository {
  _ThrowingRunOcrRepository({super.pages});

  @override
  Future<void> runOcr(int documentId, int position) async {
    throw StateError('fake: runOcr failed');
  }
}

void main() {
  Widget host(FakeDocumentRepository repo, {String? initialText}) =>
      localizedTestApp(
        home: RecognizedTextScreen(
          documentId: 1,
          position: 1,
          name: 'My Report',
          initialText: initialText,
          repository: repo,
        ),
      );

  testWidgets(
    'a runOcr failure shows the "Couldn\'t recognize text" SnackBar',
    (tester) async {
      final repo = _ThrowingRunOcrRepository(
        pages: const [PageImage(position: 1, imagePath: '/x.jpg')],
      );
      await tester.pumpWidget(host(repo, initialText: null));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('recognized-text-empty')), findsOneWidget);
      await tester.tap(find.byKey(const Key('recognized-text-run')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't recognize text"), findsOneWidget);
      // Still empty: the failed recognize did not produce text.
      expect(find.byKey(const Key('recognized-text-empty')), findsOneWidget);
    },
  );

  testWidgets(
    'a share/export failure shows the "Couldn\'t export text" SnackBar',
    (tester) async {
      final repo = FakeDocumentRepository(
        throwOnExportText: true,
        pages: const [
          PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD'),
        ],
      );
      await tester.pumpWidget(host(repo, initialText: 'HELLO WORLD'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('recognized-text-share')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't export text"), findsOneWidget);
    },
  );

  testWidgets('tapping the back button pops the screen', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/x.jpg', ocrText: 'HELLO WORLD'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('push-recognized'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RecognizedTextScreen(
                      documentId: 1,
                      position: 1,
                      name: 'My Report',
                      initialText: 'HELLO WORLD',
                      repository: repo,
                    ),
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-recognized')));
    await tester.pumpAndSettle();
    expect(find.byType(RecognizedTextScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('recognized-text-back')));
    await tester.pumpAndSettle();

    expect(find.byType(RecognizedTextScreen), findsNothing);
    expect(find.byKey(const Key('push-recognized')), findsOneWidget);
  });
}
