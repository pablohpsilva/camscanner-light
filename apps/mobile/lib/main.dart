import 'package:flutter/material.dart';

import 'features/library/home_screen.dart';
import 'features/scan/scan_dependencies.dart';

void main() => runCamScannerApp();

/// App entrypoint that accepts injectable Scan dependencies, so integration
/// tests can drive deterministic camera states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
}) {
  runApp(CamScannerApp(scanDependencies: scanDependencies));
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomeScreen(dependencies: scanDependencies),
    );
  }
}
