import 'package:flutter/material.dart';

import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';

void main() => runCamScannerApp();

/// App entrypoint with injectable Scan + Library dependencies, so integration
/// tests can drive deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
}) {
  runApp(CamScannerApp(
    scanDependencies: scanDependencies,
    libraryDependencies: libraryDependencies,
  ));
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomeScreen(
        dependencies: scanDependencies,
        libraryDependencies: libraryDependencies,
      ),
    );
  }
}
