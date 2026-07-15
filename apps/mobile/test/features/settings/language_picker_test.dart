import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

import '../../support/localized_app.dart';

void main() {
  Widget settings(LocaleController controller) => localizedTestApp(
    home: SettingsScreen(
      themeController: ThemeController(store: InMemoryThemeModeStore()),
      localeController: controller,
      feedbackAvailable: false,
    ),
  );

  testWidgets('language row shows System default initially', (tester) async {
    await tester.pumpWidget(
      settings(LocaleController(store: InMemoryLocaleStore())),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings-language')), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);
  });

  testWidgets('picker lists System default plus 11 native names', (
    tester,
  ) async {
    await tester.pumpWidget(
      settings(LocaleController(store: InMemoryLocaleStore())),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('language-option-system')), findsOneWidget);
    expect(find.text('Português (Brasil)'), findsOneWidget);
    expect(find.text('Lëtzebuergesch'), findsOneWidget);
    expect(find.text('العربية'), findsOneWidget);
  });

  testWidgets('choosing a language updates the controller and persists', (
    tester,
  ) async {
    final store = InMemoryLocaleStore();
    final controller = LocaleController(store: store);
    await tester.pumpWidget(settings(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-option-es')));
    await tester.pumpAndSettle();
    expect(controller.localeOverride, const Locale('es'));
    expect(await store.load(), const Locale('es'));
    // Row now shows the chosen autonym.
    expect(find.text('Español'), findsOneWidget);
  });

  testWidgets('System default option clears the override', (tester) async {
    final controller = LocaleController(
      store: InMemoryLocaleStore(const Locale('es')),
      initial: const Locale('es'),
    );
    await tester.pumpWidget(settings(controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-language')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('language-option-system')));
    await tester.pumpAndSettle();
    expect(controller.localeOverride, isNull);
  });
}
