import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/settings/handedness_controller.dart';
import 'package:mobile/features/settings/handedness_store.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

import '../../support/localized_app.dart';

Widget _host(
  ThemeController c, {
  bool feedbackAvailable = true,
  HandednessController? handedness,
}) => localizedTestApp(
  home: SettingsScreen(
    themeController: c,
    localeController: LocaleController(store: InMemoryLocaleStore()),
    handednessController:
        handedness ?? HandednessController(store: InMemoryHandednessStore()),
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

  testWidgets('shows the handedness selector at the current value', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    final h = HandednessController(
      store: InMemoryHandednessStore(),
      initial: Handedness.right,
    );
    await t.pumpWidget(_host(c, handedness: h));
    expect(find.byKey(const Key('settings-handedness')), findsOneWidget);
    expect(find.text('Left'), findsOneWidget);
    expect(find.text('Right'), findsOneWidget);
  });

  testWidgets('tapping Left sets the handedness controller to left', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    final h = HandednessController(
      store: InMemoryHandednessStore(),
      initial: Handedness.right,
    );
    await t.pumpWidget(_host(c, handedness: h));
    await t.tap(find.byKey(const Key('segment-Handedness.left')));
    await t.pump();
    expect(h.value, Handedness.left);
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

  testWidgets('about footer shows the app name', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    expect(find.byKey(const Key('settings-about')), findsOneWidget);
    expect(find.textContaining('ScannerCam Light'), findsOneWidget);
  });

  testWidgets('support row is shown on iOS', (t) async {
    // App Store guideline 3.1.1: iOS no longer hides every donation entry
    // point — the row now opens the IAP tip jar instead of the Ko-fi/BTC body.
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final c = ThemeController(store: InMemoryThemeModeStore());
      await t.pumpWidget(_host(c));
      expect(find.byKey(const Key('settings-support')), findsOneWidget);
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
