import 'dart:ui';

/// Every locale the app ships. `en` first (it is the template and fallback).
/// `pt` = European Portuguese, `pt_BR` = Brazilian, `zh` = Simplified Chinese.
const kSupportedAppLocales = <Locale>[
  Locale('en'),
  Locale('pt'),
  Locale('pt', 'BR'),
  Locale('es'),
  Locale('fr'),
  Locale('de'),
  Locale('lb'),
  Locale('tr'),
  Locale('ru'),
  Locale('zh'),
  Locale('ar'),
];

/// Explicit [override] wins; otherwise the first device locale with an exact
/// language+country match, then a language-only match; else English.
Locale resolveLocale(List<Locale>? deviceLocales, Locale? override) {
  if (override != null) return override;
  for (final device in deviceLocales ?? const <Locale>[]) {
    for (final supported in kSupportedAppLocales) {
      if (supported.languageCode == device.languageCode &&
          supported.countryCode != null &&
          supported.countryCode == device.countryCode) {
        return supported;
      }
    }
    for (final supported in kSupportedAppLocales) {
      if (supported.languageCode == device.languageCode &&
          supported.countryCode == null) {
        return supported;
      }
    }
  }
  return const Locale('en');
}
