import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/settings/settings_screen.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

// Per-screen dark-theme verification (Ream final phase, Task 6): every
// in-scope light-designed screen must resolve its Scaffold background to
// ReamColors.dark.paper when the app runs under the dark theme. Screens that
// need document/page fixtures (RecognizedTextScreen, PdfPreviewScreen,
// HomeScreen) are covered by a dark-theme variant added to their own sibling
// test file instead of being re-hosted here — see:
//   test/features/library/recognized_text_screen_test.dart
//   test/features/library/pdf_preview_screen_test.dart
//   test/features/library/home_screen_test.dart
Color _scaffoldBg(WidgetTester t) =>
    t.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor!;

void main() {
  Widget dark(Widget child) =>
      MaterialApp(theme: ReamTheme.dark(), home: child);

  testWidgets('DonationScreen uses dark paper', (t) async {
    await t.pumpWidget(dark(const DonationScreen()));
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });

  testWidgets('FeedbackScreen uses dark paper', (t) async {
    await t.pumpWidget(dark(const FeedbackScreen()));
    await t.pumpAndSettle();
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });

  testWidgets('SettingsScreen uses dark paper', (t) async {
    await t.pumpWidget(
      dark(
        SettingsScreen(
          themeController: ThemeController(store: InMemoryThemeModeStore()),
          localeController: LocaleController(store: InMemoryLocaleStore()),
          feedbackDependencies: const FeedbackDependencies(),
        ),
      ),
    );
    expect(_scaffoldBg(t), ReamColors.dark.paper);
  });
}
