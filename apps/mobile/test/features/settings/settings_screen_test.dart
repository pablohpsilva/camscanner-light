import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

Widget _host(ThemeController c, {bool feedbackAvailable = true}) => MaterialApp(
  theme: ReamTheme.light(),
  home: SettingsScreen(
    themeController: c,
    localeController: LocaleController(store: InMemoryLocaleStore()),
    feedbackDependencies: const FeedbackDependencies(),
    feedbackAvailable: feedbackAvailable,
  ),
);

void main() {
  testWidgets('shows the theme selector at the current mode', (t) async {
    final c = ThemeController(
      store: InMemoryThemeModeStore(),
      initial: ThemeMode.dark,
    );
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-theme-mode')), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('tapping Light sets the controller to light', (t) async {
    final c = ThemeController(
      store: InMemoryThemeModeStore(),
      initial: ThemeMode.dark,
    );
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('segment-ThemeMode.light')));
    await t.pump();
    expect(c.mode, ThemeMode.light);
  });

  testWidgets('feedback row navigates to the feedback screen', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('settings-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });

  testWidgets('support row navigates to the donation screen', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.tap(find.byKey(const Key('settings-support')));
    await t.pumpAndSettle();
    expect(
      find.textContaining('no features, benefits, or content'),
      findsOneWidget,
    );
  });

  testWidgets('feedback row is hidden when feedback is unavailable', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c, feedbackAvailable: false));
    expect(find.byKey(const Key('settings-feedback')), findsNothing);
  });

  testWidgets('about footer shows the app name and no "Ream"', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-about')), findsOneWidget);
    expect(find.textContaining('CamScanner-light'), findsOneWidget);
    expect(find.textContaining('Ream'), findsNothing);
  });

  testWidgets('support row is hidden on iOS', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final c = ThemeController(store: InMemoryThemeModeStore());
      await t.pumpWidget(_host(c));
      expect(find.byKey(const Key('settings-support')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('support row is shown on Android', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final c = ThemeController(store: InMemoryThemeModeStore());
      await t.pumpWidget(_host(c));
      expect(find.byKey(const Key('settings-support')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
