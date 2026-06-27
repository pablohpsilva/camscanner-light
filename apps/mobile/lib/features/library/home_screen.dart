import 'package:flutter/material.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
import 'widgets/empty_documents_view.dart';

/// The app's home: the document library. Shows the empty state and a Scan
/// button that opens the camera screen (A2).
class HomeScreen extends StatelessWidget {
  final ScanDependencies dependencies;

  const HomeScreen({super.key, this.dependencies = const ScanDependencies()});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: const EmptyDocumentsView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CameraScreen(dependencies: dependencies),
          ),
        ),
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}
