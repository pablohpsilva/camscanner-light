import 'package:flutter/material.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
import 'document_repository.dart';
import 'document_sort.dart';
import 'document_summary.dart';
import 'library_dependencies.dart';
import 'page_viewer_screen.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/sort_control_bar.dart';

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
  DocumentSort _sort = DocumentSort.initial;

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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
    await _refresh(); // a save may have happened while we were away
  }

  Future<void> _openDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PageViewerScreen(
          documentId: s.document.id,
          name: s.document.name,
          repository: repo,
          dependencies: widget.dependencies,
          printer: widget.libraryDependencies.printer,
          share: widget.libraryDependencies.share,
        ),
      ),
    );
    await _refresh(); // a delete may have happened in the viewer
  }

  void _openSearch() => setState(() => _searching = true);

  void _closeSearch() {
    _searchController.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    _load(); // restore the full list
  }

  Future<void> _onQueryChanged(String value) async {
    final repo = _repository;
    setState(() => _query = value);
    if (repo == null) return;
    try {
      final results = await repo.searchDocuments(value);
      if (!mounted || value != _query) return; // race guard: newer query wins
      setState(() => _summaries = results);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  // After returning from a push, re-apply search if active, else reload.
  Future<void> _refresh() => _searching ? _onQueryChanged(_query) : _load();

  void _onSortCriterion(SortCriterion c) =>
      setState(() => _sort = nextSort(_sort, c));

  Future<void> _renameDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    final newName = await showRenameDialog(context, s.document.name);
    if (newName == null) return;
    if (!mounted) return;
    try {
      await repo.rename(s.document.id, newName);
      await _refresh(); // refresh the list (no spinner; active sort re-applies)
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rename")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _searching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : _buildBody(),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
    );
  }

  AppBar _buildNormalAppBar() => AppBar(
        title: const Text('Documents'),
        actions: [
          IconButton(
            key: const Key('documents-search'),
            tooltip: 'Search',
            icon: const Icon(Icons.search),
            onPressed: _repository == null ? null : _openSearch,
          ),
        ],
      );

  AppBar _buildSearchAppBar() => AppBar(
        leading: IconButton(
          key: const Key('documents-search-close'),
          tooltip: 'Close search',
          icon: const Icon(Icons.arrow_back),
          onPressed: _closeSearch,
        ),
        title: TextField(
          key: const Key('documents-search-field'),
          controller: _searchController,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Search documents',
            border: InputBorder.none,
          ),
          onChanged: _onQueryChanged,
        ),
        actions: [
          IconButton(
            key: const Key('documents-search-clear'),
            tooltip: 'Clear',
            icon: const Icon(Icons.clear),
            onPressed: () {
              _searchController.clear();
              _onQueryChanged('');
            },
          ),
        ],
      );

  Widget _buildBody() {
    if (_searching) {
      if (_summaries.isEmpty && _query.trim().isNotEmpty) {
        return Center(
          key: const Key('documents-search-empty'),
          child: Text('No documents match "$_query".'),
        );
      }
      if (_summaries.isEmpty) return const EmptyDocumentsView();
      return DocumentsListView(
        summaries: _summaries,
        onOpen: _openDocument,
        onRename: _renameDocument,
      );
    }
    if (_summaries.isEmpty) return const EmptyDocumentsView();
    return Column(
      children: [
        SortControlBar(sort: _sort, onCriterionTapped: _onSortCriterion),
        Expanded(
          child: DocumentsListView(
            summaries: sortDocuments(_summaries, _sort),
            onOpen: _openDocument,
            onRename: _renameDocument,
          ),
        ),
      ],
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
