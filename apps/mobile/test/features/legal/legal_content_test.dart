import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/l10n/locale_resolution.dart';

void main() {
  test('returns the English document for en', () {
    final d = legalDocument(LegalDoc.terms, const Locale('en'));
    expect(d.title, 'Terms of Service');
    expect(d.translationNotice, isEmpty);
    expect(d.sections, isNotEmpty);
  });

  test(
    'returns a translated document with a notice for a non-English locale',
    () {
      final d = legalDocument(LegalDoc.terms, const Locale('de'));
      expect(d.title, isNot('Terms of Service'));
      expect(d.translationNotice, isNotEmpty);
    },
  );

  test('distinguishes pt from pt_BR', () {
    final pt = legalDocument(LegalDoc.faq, const Locale('pt'));
    final br = legalDocument(LegalDoc.faq, const Locale('pt', 'BR'));
    expect(pt.sections.length, br.sections.length);
  });

  test('falls back to English for an unsupported locale', () {
    final d = legalDocument(LegalDoc.privacy, const Locale('ja'));
    expect(d.title, legalDocument(LegalDoc.privacy, const Locale('en')).title);
  });

  test('falls back to the base language when the country is unknown', () {
    final d = legalDocument(LegalDoc.privacy, const Locale('pt', 'AO'));
    expect(d.title, legalDocument(LegalDoc.privacy, const Locale('pt')).title);
  });

  test('every document exists in every supported locale', () {
    for (final doc in LegalDoc.values) {
      for (final locale in kSupportedAppLocales) {
        final d = legalDocument(doc, locale);
        expect(d.sections, isNotEmpty, reason: '$doc/$locale is empty');
        expect(d.effectiveDate, isNotEmpty);
      }
    }
  });

  test('all locales of a document share the same section ids', () {
    for (final doc in LegalDoc.values) {
      final en = legalDocument(
        doc,
        const Locale('en'),
      ).sections.map((s) => s.id).toList();
      for (final locale in kSupportedAppLocales) {
        expect(
          legalDocument(doc, locale).sections.map((s) => s.id).toList(),
          en,
          reason: '$doc/$locale diverges from English',
        );
      }
    }
  });
}
