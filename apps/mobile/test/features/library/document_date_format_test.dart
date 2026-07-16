import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile/features/library/document_date_format.dart';

/// P15 dup-date-format: the grid card used a hardcoded English `months[]` array
/// (an i18n regression); both views now share locale-aware intl formatters over
/// the SAME timestamp. These assert the compact/grid date is localized (differs
/// en vs de) and that both formatters read the same instant.
void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  final date = DateTime(2026, 6, 27, 20, 26);

  group('formatDocumentDateCompact (grid)', () {
    test('is localized — English month abbreviation', () {
      expect(formatDocumentDateCompact(date, 'en'), contains('Jun'));
      expect(formatDocumentDateCompact(date, 'en'), contains('27'));
    });

    test('is localized — German differs from English', () {
      final en = formatDocumentDateCompact(date, 'en');
      final de = formatDocumentDateCompact(date, 'de');
      expect(de, isNot(equals(en)));
      expect(de, contains('Juni')); // German month name, not "Jun"
    });

    test('no hardcoded English months leak for a non-English locale', () {
      // The old bug: December in German still rendered "Dec".
      final dec = DateTime(2026, 12, 3);
      expect(formatDocumentDateCompact(dec, 'de'), isNot(contains('Dec')));
      expect(formatDocumentDateCompact(dec, 'de'), contains('Dez'));
    });
  });

  group('formatDocumentDateDetailed (list)', () {
    test('includes the time of day and is localized', () {
      final en = formatDocumentDateDetailed(date, 'en');
      expect(en, contains('20:26'));
      expect(en, contains('2026'));
      final de = formatDocumentDateDetailed(date, 'de');
      expect(de, contains('20:26'));
      expect(de, isNot(equals(en))); // date-part order differs by locale
    });
  });
}
