import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/l10n/locale_controller.dart';
import 'package:mobile/l10n/locale_store.dart';
import 'package:mobile/theme/theme_controller.dart';
import 'package:mobile/theme/theme_mode_store.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';
import '../../support/localized_app.dart';

class _SpyThemeController extends ThemeController {
  bool disposed = false;
  _SpyThemeController() : super(store: InMemoryThemeModeStore());
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

class _SpyLocaleController extends LocaleController {
  bool disposed = false;
  _SpyLocaleController() : super(store: InMemoryLocaleStore());
  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

void main() {
  testWidgets('P06 task 4: INJECTED theme/locale controllers are NOT disposed '
      'by HomeScreen (the caller still owns them)', (tester) async {
    final theme = _SpyThemeController();
    final locale = _SpyLocaleController();

    await tester.pumpWidget(
      localizedTestApp(
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
          themeController: theme,
          localeController: locale,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Tear HomeScreen down.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    expect(
      theme.disposed,
      isFalse,
      reason: 'injected controller is caller-owned',
    );
    expect(locale.disposed, isFalse);

    // Still usable after HomeScreen is gone (would throw if wrongly disposed).
    theme.dispose();
    locale.dispose();
  });

  testWidgets('the fallback controllers are disposed cleanly (no leak, no '
      'exception) when none are injected', (tester) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();

    // A double-dispose of an owned ChangeNotifier would throw; disposing the
    // fallbacks in HomeScreen.dispose must not leak a live notifier or throw.
    expect(tester.takeException(), isNull);
  });
}
