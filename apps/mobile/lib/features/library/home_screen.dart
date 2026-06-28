import 'package:flutter/material.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
import 'document_repository.dart';
import 'document_summary.dart';
import 'library_dependencies.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';

/// The app's home: the document library. Builds the repository, lists saved
/// documents (name + date), and opens the camera. Reloads the list whenever the
/// camera flow returns (a save may have happened).
class HomeScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final LibraryDependencies libraryDependencies;

  const HomeScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DocumentRepository? _repository;
  List<DocumentSummary> _summaries = const [];
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final repo = await widget.libraryDependencies.createRepository();
      if (!mounted) return;
      _repository = repo;
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final docs = await repo.listDocumentSummaries();
      if (!mounted) return;
      setState(() {
        _summaries = docs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = true;
        });
      }
    }
  }

  void _retry() {
    setState(() {
      _error = false;
      _loading = true;
    });
    _init();
  }

  Future<void> _openScan() async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CameraScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _load(); // a save may have happened while we were away
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : _summaries.isEmpty
                  ? const EmptyDocumentsView()
                  : DocumentsListView(summaries: _summaries),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _repository == null ? null : _openScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      key: const Key('documents-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text("Couldn't load documents."),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('documents-retry'),
            onPressed: _retry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
