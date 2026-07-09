import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../scan/capture_review_screen.dart';
import '../scan/captured_image.dart';
import '../scan/id_scan_screen.dart';
import '../scan/scan_screen.dart';
import '../scan/scan_dependencies.dart';
import 'document_repository.dart';
import 'document_sort.dart';
import 'document_summary.dart';
import 'library_dependencies.dart';
import 'page_viewer_screen.dart';
import 'save_controller.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/sort_control_bar.dart';
import '../donation/donation_banner.dart';
import '../feedback/feedback_dependencies.dart';
import '../feedback/feedback_screen.dart';

/// The app's home: the document library. Builds the repository, lists saved
/// documents (name + date), and opens the camera. Reloads the list whenever the
/// camera flow returns (a save may have happened).
class HomeScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;

  const HomeScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
  });

  // Aggressive cold-start watchdog budget. Every startup step must finish within
  // this or the app is treated as wedged (e.g. a native DB open that never
  // resolves) and a named error is surfaced instead of an endless white/spinner
  // screen. "Opens but never loads" is thus impossible to ship silently again.
  static const Duration coldStartStepTimeout = Duration(seconds: 10);

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DocumentRepository? _repository;
  List<DocumentSummary> _summaries = const [];
  bool _loading = true;
  bool _error = false;
  DocumentSort _sort = DocumentSort.initial;
  bool _feedbackAvailable = false;

  final TextEditingController _searchController = TextEditingController();
  bool _searching = false;
  String _query = '';
  bool _sharing = false;
  final Set<int> _selectedIds = <int>{};
  bool get _selectionMode => _selectedIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _init();
    _probeFeedback();
  }

  Future<void> _probeFeedback() async {
    final available =
        await widget.feedbackDependencies.availability().isAvailable();
    if (mounted) setState(() => _feedbackAvailable = available);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Set when a startup step failed or timed out, so the error screen can name
  // the stuck step (and it's logged for on-device diagnosis).
  String? _startupFailure;

  Future<void> _init() async {
    try {
      final repo = await widget.libraryDependencies.createRepository().timeout(
        HomeScreen.coldStartStepTimeout,
      );
      if (!mounted) return;
      _repository = repo;
      await _load();
    } catch (e) {
      _failStartup('opening the library', e);
    }
  }

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final docs = await repo.listDocumentSummaries().timeout(
        HomeScreen.coldStartStepTimeout,
      );
      if (!mounted) return;
      setState(() {
        _summaries = docs;
        _loading = false;
        _startupFailure = null;
      });
    } catch (e) {
      _failStartup('loading your documents', e);
    }
  }

  void _failStartup(String step, Object error) {
    // Always logged so a wedged cold start is diagnosable from device logs.
    debugPrint('HomeScreen cold-start failed while $step: $error');
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = true;
      _startupFailure = 'Startup timed out while $step.';
    });
  }

  void _retry() {
    setState(() {
      _error = false;
      _loading = true;
      _startupFailure = null;
    });
    _init();
  }

  Future<void> _openScan() async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScanScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _refresh(); // a save may have happened while we were away
  }

  Future<void> _openIdScan() async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            IdScanScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _refresh();
  }

  Future<void> _onImport() async {
    final repo = _repository;
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    CapturedImage? image;
    try {
      image = await widget.dependencies.createGalleryPicker().pick();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't import photo")),
      );
      return;
    }
    if (image == null) return; // user cancelled
    if (!mounted) return;

    final capturedImage = image;
    final navigator = Navigator.of(context);
    final edgeDetector = widget.dependencies.createEdgeDetector();
    final saveController = SaveController(repository: repo);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: capturedImage,
            enableCrop: true,
            edgeDetector: edgeDetector,
            saving: saveController.saving,
            onRetake: () => navigator.pop(),
            onAccept: (corners, enhancer) async {
              final doc = await saveController.save(
                capturedImage,
                corners: corners,
                enhancer: enhancer,
              );
              if (!mounted) return;
              if (doc == null) {
                messenger.showSnackBar(
                  const SnackBar(
                      content: Text("Couldn't save document. Try again.")),
                );
                return;
              }
              navigator.pop();
              await _refresh();
            },
          ),
        ),
      ),
    );
    saveController.dispose();
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

  void _openSearch() => setState(() {
    _selectedIds.clear();
    _searching = true;
  });

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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't rename")));
    }
  }

  Future<void> _shareDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null || _sharing) return;
    _sharing = true;
    try {
      final file = await repo.exportPdf(s.document.id);
      await widget.libraryDependencies.share.share([
        file.path,
      ], subject: s.document.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share")));
    } finally {
      _sharing = false;
    }
  }

  void _toggleSelect(DocumentSummary s) {
    setState(() {
      final id = s.document.id;
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  void _startSelection(DocumentSummary s) {
    setState(() => _selectedIds.add(s.document.id));
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  // The documents currently on screen, in display order (search order when
  // searching, else the active sort). Selection export follows this order.
  List<DocumentSummary> get _displayed =>
      _searching ? _summaries : sortDocuments(_summaries, _sort);

  Future<void> _exportSelected() async {
    final repo = _repository;
    if (repo == null || _sharing) return;
    final selected = _displayed
        .where((s) => _selectedIds.contains(s.document.id))
        .toList();
    if (selected.isEmpty) return;
    final ids = selected.map((s) => s.document.id).toList();

    _sharing = true;
    try {
      final share = widget.libraryDependencies.share;
      if (ids.length == 1) {
        final file = await repo.exportPdf(ids.first);
        await share.share([file.path], subject: selected.first.document.name);
      } else {
        final files = await repo.exportSeparatePdfs(ids);
        // Reuse the repo's sanitized per-doc PDF names as zip entry names (DRY).
        final entryNames = [for (final f in files) p.basename(f.path)];
        final zip = await widget.libraryDependencies.archiver.zip(
          files,
          archiveName: 'documents.zip',
          entryNames: entryNames,
        );
        await share.share([zip.path], mimeType: 'application/zip');
      }
      if (mounted) _clearSelection();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share")));
    } finally {
      _sharing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _selectionMode
          ? _buildSelectionAppBar()
          : _searching
          ? _buildSearchAppBar()
          : _buildNormalAppBar(),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator(),
            )
          : _error
          ? _buildError()
          : _buildBody(),
      floatingActionButton: (_searching || _selectionMode)
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
      bottomNavigationBar: const DonationBanner(),
    );
  }

  AppBar _buildSelectionAppBar() => AppBar(
    leading: IconButton(
      key: const Key('selection-close'),
      tooltip: 'Cancel selection',
      icon: const Icon(Icons.close),
      onPressed: _clearSelection,
    ),
    title: Text('${_selectedIds.length} selected'),
    actions: [
      IconButton(
        key: const Key('selection-export'),
        tooltip: 'Export',
        icon: const Icon(Icons.ios_share),
        onPressed: _exportSelected,
      ),
    ],
  );

  AppBar _buildNormalAppBar() => AppBar(
    title: const Text('Documents'),
    actions: [
      IconButton(
        key: const Key('home-scan-id'),
        tooltip: 'Scan ID card',
        icon: const Icon(Icons.badge_outlined),
        onPressed: _repository == null ? null : _openIdScan,
      ),
      IconButton(
        key: const Key('home-import'),
        tooltip: 'Import from gallery',
        icon: const Icon(Icons.photo_library_outlined),
        onPressed: _repository == null ? null : _onImport,
      ),
      IconButton(
        key: const Key('documents-search'),
        tooltip: 'Search',
        icon: const Icon(Icons.search),
        onPressed: _repository == null ? null : _openSearch,
      ),
      if (_feedbackAvailable)
        PopupMenuButton<String>(
          key: const Key('home-overflow-menu'),
          onSelected: (v) {
            if (v == 'feedback') {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) =>
                    FeedbackScreen(dependencies: widget.feedbackDependencies),
              ));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              key: Key('home-menu-feedback'),
              value: 'feedback',
              child: Text('Send feedback'),
            ),
          ],
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
        onShare: _shareDocument,
        selectionMode: _selectionMode,
        selectedIds: _selectedIds,
        onToggleSelect: _toggleSelect,
        onLongPress: _startSelection,
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
            onShare: _shareDocument,
            selectionMode: _selectionMode,
            selectedIds: _selectedIds,
            onToggleSelect: _toggleSelect,
            onLongPress: _startSelection,
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
          Text(_startupFailure ?? "Couldn't load documents."),
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
