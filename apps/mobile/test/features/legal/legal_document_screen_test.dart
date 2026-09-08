import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/features/legal/legal_document_screen.dart';

import '../../support/localized_app.dart';

Widget _host(LegalDoc doc, {Locale locale = const Locale('en'), List<Uri>? opened}) =>
    localizedTestApp(
      locale: locale,
      home: LegalDocumentScreen(
        doc: doc,
        openUrl: (uri) async {
          opened?.add(uri);
          return true;
        },
      ),
    );

void main() {
  testWidgets('shows the document title in the header', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('shows the effective date', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.textContaining('2026-09-08'), findsOneWidget);
  });

  testWidgets('renders every section heading of the terms', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    final doc = legalDocument(LegalDoc.terms, const Locale('en'));
    // Scroll through so off-screen headings are built.
    for (final section in doc.sections) {
      await t.scrollUntilVisible(find.text(section.heading), 300);
      expect(find.text(section.heading), findsOneWidget);
    }
  });

  testWidgets('hides the translation notice in English', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.byKey(const Key('legal-translation-notice')), findsNothing);
  });

  testWidgets('shows the translation notice in German', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms, locale: const Locale('de')));
    expect(find.byKey(const Key('legal-translation-notice')), findsOneWidget);
  });

  testWidgets('the FAQ renders collapsed questions that expand on tap', (t) async {
    await t.pumpWidget(_host(LegalDoc.faq));
    final doc = legalDocument(LegalDoc.faq, const Locale('en'));
    final first = doc.sections.first;
    final answer = (first.body.first as dynamic).text as String;
    expect(find.text(first.heading), findsOneWidget);
    expect(find.textContaining(answer.substring(0, 12)), findsNothing);
    await t.tap(find.text(first.heading));
    await t.pumpAndSettle();
    expect(find.textContaining(answer.substring(0, 12)), findsOneWidget);
  });

  testWidgets('tapping an inline link opens it through the injected opener', (t) async {
    final opened = <Uri>[];
    await t.pumpWidget(_host(LegalDoc.terms, opened: opened));
    await t.scrollUntilVisible(find.byKey(const Key('legal-section-contact')), 300);
    await t.tap(find.textContaining('scannercamlight.line149@passmail.net').first);
    await t.pumpAndSettle();
    expect(opened.single.scheme, 'mailto');
  });

  // CRITICAL: sibling-document links ("privacy.html", "terms.html",
  // "faq.html") are relative URIs the platform url_launcher cannot resolve
  // (silently fails under LaunchMode.externalApplication — no crash, no
  // error, just a dead link, in all 11 languages). They must navigate
  // in-app instead of ever reaching the injected opener.
  testWidgets(
    'tapping a sibling-document link navigates in-app and never calls the opener',
    (t) async {
      final opened = <Uri>[];
      await t.pumpWidget(_host(LegalDoc.terms, opened: opened));
      await t.scrollUntilVisible(find.byKey(const Key('legal-section-acceptance')), 300);

      await t.tap(find.textContaining('Privacy Policy').first);
      await t.pumpAndSettle();

      expect(opened, isEmpty, reason: 'a relative sibling link must never reach the URL opener');
      // The pushed screen is the Privacy Policy document.
      expect(find.text('Privacy Policy'), findsOneWidget);
    },
  );
}
