import 'package:flutter/material.dart';

import 'core/logging/app_logger.dart';
import 'features/feedback/feedback_dependencies.dart';
import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';
import 'features/settings/handedness_controller.dart';
import 'features/settings/handedness_store.dart';
import 'l10n/l10n.dart';
import 'l10n/lb_fallback_delegates.dart';
import 'l10n/locale_controller.dart';
import 'l10n/locale_resolution.dart';
import 'l10n/locale_store.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_mode_store.dart';

/// Routes uncaught framework errors to [logger] while preserving Flutter's
/// default debug presentation (red screen / console dump).
void installGlobalErrorHandling(AppLogger logger) {
  FlutterError.onError = (details) {
    logger.error(
      details.exception,
      stackTrace: details.stack,
      context: 'FlutterError',
    );
    FlutterError.presentError(details);
  };
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installGlobalErrorHandling(const PrintAppLogger());
  final store = SharedPrefsThemeModeStore();
  final controller = ThemeController(
    store: store,
    initial: await store.load() ?? ThemeMode.dark,
  );
  final localeStore = SharedPrefsLocaleStore();
  final localeController = LocaleController(
    store: localeStore,
    initial: await localeStore.load(),
  );
  final handednessStore = SharedPrefsHandednessStore();
  final handednessController = HandednessController(
    store: handednessStore,
    initial: await handednessStore.load() ?? Handedness.right,
  );
  runCamScannerApp(
    themeController: controller,
    localeController: localeController,
    handednessController: handednessController,
  );
}

/// App entrypoint with injectable dependencies, so integration tests can drive
/// deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
  FeedbackDependencies feedbackDependencies = const FeedbackDependencies(),
  ThemeController? themeController,
  LocaleController? localeController,
  HandednessController? handednessController,
}) {
  runApp(
    CamScannerApp(
      scanDependencies: scanDependencies,
      libraryDependencies: libraryDependencies,
      feedbackDependencies: feedbackDependencies,
      themeController:
          themeController ??
          ThemeController(store: SharedPrefsThemeModeStore()),
      // ..load() so a default-wired app (integration-test relaunch) picks up
      // the persisted choice without an async entrypoint.
      localeController:
          localeController ??
          (LocaleController(store: SharedPrefsLocaleStore())..load()),
      handednessController:
          handednessController ??
          (HandednessController(store: SharedPrefsHandednessStore())..load()),
    ),
  );
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;
  final ThemeController themeController;
  final LocaleController localeController;
  final HandednessController handednessController;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
    required this.themeController,
    required this.localeController,
    required this.handednessController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        themeController,
        localeController,
        handednessController,
      ]),
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => context.l10n.appTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: themeController.mode,
        locale: localeController.localeOverride,
        supportedLocales: kSupportedAppLocales,
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        localeListResolutionCallback: (locales, supported) =>
            resolveLocale(locales, localeController.localeOverride),
        home: HomeScreen(
          dependencies: scanDependencies,
          libraryDependencies: libraryDependencies,
          feedbackDependencies: feedbackDependencies,
          themeController: themeController,
          localeController: localeController,
          handednessController: handednessController,
        ),
      ),
    );
  }
}
