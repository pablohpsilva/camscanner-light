import 'package:flutter/material.dart';
import 'features/library/home_screen.dart';

void main() {
  runApp(const CamScannerApp());
}

class CamScannerApp extends StatelessWidget {
  const CamScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
