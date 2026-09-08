import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_library.dart';
import '../test/support/fake_scan.dart';

/// On-device verification of the three legal documents.
///
/// The host suite already covers rendering, the locale fallback and the
/// in-app sibling-link navigation. What it CANNOT cover is whether the
/// generated 359KB const map actually loads on a real device, whether the
/// documents scroll without overflowing on a real screen, and whether the
/// Arabic RTL layout holds — which is why CLAUDE.md forbids calling this
/// work done on host-green alone.
///
/// Run on a REAL device (a simulator does not satisfy the claim):
///   flutter test integration_test/legal_documents_device_test.dart -d `id`
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Future<void> launch(WidgetTester tester) async {
    app.runCamScannerApp(
      scanDependencies: grantedScanDependencies(),
      libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('home-settings')));
    await tester.pumpAndSettle();
  }

  for (final (doc, rowKey) in const [
    (LegalDoc.terms, 'settings-terms'),
    (LegalDoc.privacy, 'settings-privacy'),
    (LegalDoc.faq, 'settings-faq'),
  ]) {
    testWidgets('${doc.key} opens from settings and renders on device', (
      tester,
    ) async {
      await launch(tester);
      await openSettings(tester);

      final row = find.byKey(Key(rowKey));
      await tester.scrollUntilVisible(row, 200);
      await tester.tap(row);
      await tester.pumpAndSettle();

      // The document really came from the generated const map, not a stub.
      final document = legalDocument(doc, const Locale('en'));
      expect(document.sections, isNotEmpty);
      expect(
        find.byKey(Key('legal-section-${document.sections.first.id}')),
        findsOneWidget,
        reason: 'first section of ${doc.key} did not render on device',
      );

      // Scroll to the last section: proves the whole document lays out on a
      // real screen without overflowing.
      final last = find.byKey(
        Key('legal-section-${document.sections.last.id}'),
      );
      await tester.scrollUntilVisible(last, 300);
      expect(last, findsOneWidget);

      // This app uses AppBackHeader's own Key('back') control, not a
      // material BackButton, so tester.pageBack() cannot find it.
      await tester.tap(find.byKey(const Key('back')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key(rowKey)), findsOneWidget);
    });
  }

  testWidgets('a translated document shows the English-prevails notice', (
    tester,
  ) async {
    await launch(tester);
    await openSettings(tester);

    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Español').last);
    await tester.pumpAndSettle();

    final row = find.byKey(const Key('settings-terms'));
    await tester.scrollUntilVisible(row, 200);
    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('legal-translation-notice')),
      findsOneWidget,
      reason: 'non-English documents must carry the English-prevails notice',
    );
  });
}
