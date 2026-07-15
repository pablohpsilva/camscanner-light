import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_resolution.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/main.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

Widget _app(LocaleController locale) => CamScannerApp(
  scanDependencies: grantedScanDependencies(),
  libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
  themeController: ThemeController(store: InMemoryThemeModeStore()),
  localeController: locale,
);

void main() {
  testWidgets('MaterialApp exposes supported locales and delegates', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(LocaleController(store: InMemoryLocaleStore())),
    );
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.supportedLocales, kSupportedAppLocales);
    expect(app.locale, isNull); // system default
    expect(app.localeListResolutionCallback, isNotNull);
    // Unsupported device language resolves to English.
    expect(
      app.localeListResolutionCallback!([
        const Locale('ja'),
      ], app.supportedLocales.toList()),
      const Locale('en'),
    );
  });

  testWidgets('controller override drives MaterialApp.locale live', (
    tester,
  ) async {
    final controller = LocaleController(store: InMemoryLocaleStore());
    await tester.pumpWidget(_app(controller));
    await tester.pumpAndSettle();
    await controller.setLocale(const Locale('es'));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('es'));
  });

  testWidgets('app title is localized via onGenerateTitle', (tester) async {
    await tester.pumpWidget(
      _app(LocaleController(store: InMemoryLocaleStore())),
    );
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.onGenerateTitle, isNotNull);
  });
}
