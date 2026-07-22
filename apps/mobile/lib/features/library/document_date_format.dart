import 'package:intl/intl.dart';

/// Localized document-date formatting (P15 dup-date-format). The documents list
/// and the grid card now format the SAME timestamp — the document's `createdAt`
/// — through locale-aware `intl` formats, closing the grid card's hardcoded
/// English `months[]` i18n regression (the app ships 11 languages). The two
/// views differ only in granularity: the detailed list row keeps the time of
/// day; the compact grid card shows a short month + day.
///
/// [locale] is the current UI locale name (e.g. `en`, `de`, `en_US`); pass
/// `Localizations.localeOf(context).toString()`.

/// Detailed date + time for the list row, e.g. `en` → "6/27/2026 20:26",
/// `de` → "27.6.2026 20:26".
String formatDocumentDateDetailed(DateTime local, String locale) =>
    DateFormat.yMd(_intlLocale(locale)).add_Hm().format(local);

/// Compact localized month + day for the grid card, e.g. `en` → "Jun 27",
/// `de` → "27. Juni".
String formatDocumentDateCompact(DateTime local, String locale) =>
    DateFormat.MMMd(_intlLocale(locale)).format(local);

/// `intl` ships date-symbol data for every locale the app supports EXCEPT
/// Luxembourgish (`lb`) — feeding `lb` to [DateFormat] throws `ArgumentError`,
/// which used to crash while building every document card and render the whole
/// home-screen list as a grey ErrorWidget for Luxembourgish users with saved
/// documents. The app already serves German framework strings for `lb` (see
/// `lb_fallback_delegates.dart`), so format `lb` dates with German too —
/// consistent with the rest of the UI and, crucially, crash-free.
String _intlLocale(String locale) =>
    locale == 'lb' || locale.startsWith('lb_') ? 'de' : locale;
