import 'dart:ui';

import '../../l10n/locale_store.dart' show localeTag;
import 'generated/legal_content.g.dart';
import 'legal_doc.dart';
import 'legal_models.dart';

/// The document [doc] in [locale].
///
/// Resolution order: exact tag ('pt_BR'), then the base language ('pt'), then
/// English. English always exists, so this never returns null — a missing
/// translation degrades to a readable document rather than an empty screen.
LegalDocument legalDocument(LegalDoc doc, Locale locale) {
  final byLocale = kLegalContent[doc.key]!;
  return byLocale[localeTag(locale)] ??
      byLocale[locale.languageCode] ??
      byLocale['en']!;
}
