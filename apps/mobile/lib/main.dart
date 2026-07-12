import 'package:flutter/material.dart';

import 'features/feedback/feedback_dependencies.dart';
import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';
import 'theme/ream_theme.dart';
import 'theme/theme_controller.dart';
import 'theme/theme_mode_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = SharedPrefsThemeModeStore();
  final controller = ThemeController(
    store: store,
    initial: await store.load() ?? ThemeMode.dark,
  );
  runCamScannerApp(themeController: controller);
}

/// App entrypoint with injectable dependencies, so integration tests can drive
/// deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
  FeedbackDependencies feedbackDependencies = const FeedbackDependencies(),
  ThemeController? themeController,
}) {
  runApp(
    CamScannerApp(
      scanDependencies: scanDependencies,
      libraryDependencies: libraryDependencies,
      feedbackDependencies: feedbackDependencies,
      themeController:
          themeController ??
          ThemeController(store: SharedPrefsThemeModeStore()),
    ),
  );
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;
  final ThemeController themeController;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
    required this.themeController,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) => MaterialApp(
        title: 'CamScanner-light',
        debugShowCheckedModeBanner: false,
        theme: ReamTheme.light(),
        darkTheme: ReamTheme.dark(),
        themeMode: themeController.mode,
        home: HomeScreen(
          dependencies: scanDependencies,
          libraryDependencies: libraryDependencies,
          feedbackDependencies: feedbackDependencies,
          themeController: themeController,
        ),
      ),
    );
  }
}
