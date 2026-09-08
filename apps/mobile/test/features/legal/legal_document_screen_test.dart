import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/features/legal/legal_document_screen.dart';

import '../../support/localized_app.dart';

Widget _host(
  LegalDoc doc, {
  Locale locale = const Locale('en'),
  List<Uri>? opened,
}) => localizedTestApp(
  locale: locale,
  home: LegalDocumentScreen(
    doc: doc,
    openUrl: (uri) async {
      opened?.add(uri);
      return true;
    },
  ),
);

/// Host whose opener FAILS, either by returning false or by throwing.
Widget _failingHost(LegalDoc doc, {required bool throws}) => localizedTestApp(
  home: LegalDocumentScreen(
    doc: doc,
    openUrl: (uri) async {
      if (throws) throw Exception('no handler');
      return false;
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

  testWidgets('the FAQ renders collapsed questions that expand on tap', (
    t,
  ) async {
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

  testWidgets('tapping an inline link opens it through the injected opener', (
    t,
  ) async {
    final opened = <Uri>[];
    await t.pumpWidget(_host(LegalDoc.terms, opened: opened));
    await t.scrollUntilVisible(
      find.byKey(const Key('legal-section-contact')),
      300,
    );
    await t.tap(
      find.textContaining('scannercamlight.line149@passmail.net').first,
    );
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
      await t.scrollUntilVisible(
        find.byKey(const Key('legal-section-acceptance')),
        300,
      );

      await t.tap(find.textContaining('Privacy Policy').first);
      await t.pumpAndSettle();

      expect(
        opened,
        isEmpty,
        reason: 'a relative sibling link must never reach the URL opener',
      );
      // The pushed screen is the Privacy Policy document.
      expect(find.text('Privacy Policy'), findsOneWidget);
    },
  );

  // The only link that reaches the opener after sibling interception is the
  // contact `mailto:`, present in all 3 documents x 11 locales. url_launcher
  // returns false OR throws depending on the failure, and a device with no mail
  // client is routine on Android. Both paths previously produced silence: the
  // Future was dropped, so nothing told the user the tap did nothing.
  for (final throws in [false, true]) {
    testWidgets(
      'a link that fails to open (${throws ? "throws" : "returns false"}) tells the user',
      (t) async {
        await t.pumpWidget(_failingHost(LegalDoc.privacy, throws: throws));
        await t.pumpAndSettle();

        // The contact section is the last one; scroll it into view so its
        // RichText is actually built.
        await t.scrollUntilVisible(
          find.byKey(const Key('legal-section-contact')),
          400,
        );
        await t.pumpAndSettle();

        final recognizer = _mailtoRecognizer(t);
        expect(
          recognizer,
          isNotNull,
          reason: 'contact mailto link should render',
        );
        recognizer!.onTap!();
        await t.pumpAndSettle();

        expect(find.byType(SnackBar), findsOneWidget);
      },
    );
  }
}

/// Finds the tap recognizer attached to the contact `mailto:` span.
TapGestureRecognizer? _mailtoRecognizer(WidgetTester t) {
  for (final w in t.widgetList<RichText>(find.byType(RichText))) {
    TapGestureRecognizer? found;
    w.text.visitChildren((span) {
      if (span is TextSpan &&
          span.recognizer is TapGestureRecognizer &&
          (span.text ?? '').contains('scannercamlight')) {
        found = span.recognizer as TapGestureRecognizer;
        return false;
      }
      return true;
    });
    if (found != null) return found;
  }
  return null;
}
