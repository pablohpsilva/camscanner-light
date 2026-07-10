import 'package:flutter/material.dart';

import 'features/feedback/feedback_dependencies.dart';
import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';
import 'theme/ream_theme.dart';

void main() => runCamScannerApp();

/// App entrypoint with injectable Scan + Library dependencies, so integration
/// tests can drive deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
  FeedbackDependencies feedbackDependencies = const FeedbackDependencies(),
}) {
  runApp(
    CamScannerApp(
      scanDependencies: scanDependencies,
      libraryDependencies: libraryDependencies,
      feedbackDependencies: feedbackDependencies,
    ),
  );
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ReamTheme.light(),
      darkTheme: ReamTheme.dark(),
      themeMode:
          ThemeMode.light, // light-first; dark verified in the final phase
      home: HomeScreen(
        dependencies: scanDependencies,
        libraryDependencies: libraryDependencies,
        feedbackDependencies: feedbackDependencies,
      ),
    );
  }
}
