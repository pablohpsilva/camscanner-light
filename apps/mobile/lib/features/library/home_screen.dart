import 'package:flutter/material.dart';
import 'widgets/empty_documents_view.dart';

/// The app's home: the document library. For A1 it always shows the empty
/// state and a Scan button that does nothing yet (wired to the camera in A2).
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: const EmptyDocumentsView(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {}, // A1: no action yet — A2 opens the camera
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}
