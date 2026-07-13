import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../scan/capture_review_screen.dart';
import '../scan/captured_image.dart';
import '../scan/id_scan_screen.dart';
import '../scan/scan_screen.dart';
import '../scan/scan_dependencies.dart';
import '../../theme/ream_colors.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_mode_store.dart';
import '../../theme/widgets/ream_action_button.dart';
import '../../theme/widgets/ream_search_field.dart';
import '../../theme/widgets/ream_segmented.dart';
import 'document_repository.dart';
import 'document_sort.dart';
import 'document_summary.dart';
import 'folder.dart';
import 'library_dependencies.dart';
import 'library_view_mode.dart';
import 'page_viewer_screen.dart';
import 'save_controller.dart';
import 'tag.dart';
import 'widgets/create_folder_dialog.dart';
import 'widgets/documents_grid_view.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';
import 'widgets/folder_filter_bar.dart';
import 'widgets/manage_tags_sheet.dart';
import 'widgets/move_to_folder_sheet.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/sort_pill.dart';
import 'widgets/tag_filter_sheet.dart';
import '../donation/donation_banner.dart';
import '../feedback/feedback_dependencies.dart';
import '../settings/settings_screen.dart';

/// The app's home: the document library. Builds the repository, lists saved
/// documents (name + date), and opens the camera. Reloads the list whenever the
/// camera flow returns (a save may have happened).
class HomeScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;
  final ThemeController? themeController;

  const HomeScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
    this.themeController,
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
  LibraryViewMode _viewMode = LibraryViewMode.list;
  List<Folder> _folders = const [];
  FolderFilter _folderFilter = const FolderFilter.all();
  List<Tag> _tags = const [];
  Set<int> _activeTagIds = <int>{};
  late final ThemeController _themeController =
      widget.themeController ??
      ThemeController(store: InMemoryThemeModeStore());

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  // The FTS results for the current non-empty query. Kept separate from
  // [_summaries] (the full list) so clearing the query restores the full list
  // without a re-query.
  List<DocumentSummary> _searchResults = const [];
  bool _sharing = false;
  final Set<int> _selectedIds = <int>{};
  bool get _selectionMode => _selectedIds.isNotEmpty;
  bool get _searching => _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _init();
    _probeFeedback();
  }

  Future<void> _probeFeedback() async {
    final available = await widget.feedbackDependencies
        .availability()
        .isAvailable();
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
      final folders = await repo.listFolders().timeout(
        HomeScreen.coldStartStepTimeout,
      );
      final tags = await repo.listTags().timeout(
        HomeScreen.coldStartStepTimeout,
      );
      if (!mounted) return;
      setState(() {
        _summaries = docs;
        _folders = folders;
        _tags = tags;
        _loading = false;
        _startupFailure = null;
      });
    } catch (e) {
      _failStartup('loading your documents', e);
    }
  }

  // folderId (null = unfiled) -> document count, computed from the loaded
  // summaries so the bar's counts always reflect what's on screen.
  Map<int?, int> _folderCounts() {
    final counts = <int?, int>{};
    for (final s in _summaries) {
      counts[s.folderId] = (counts[s.folderId] ?? 0) + 1;
    }
    return counts;
  }

  Future<void> _createFolder() async {
    final repo = _repository;
    if (repo == null) return;
    final name = await showCreateFolderDialog(context);
    if (name == null) return;
    if (!mounted) return;
    try {
      await repo.createFolder(name);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't create folder")));
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
                    content: Text("Couldn't save document. Try again."),
                  ),
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
          features: widget.libraryDependencies.features,
        ),
      ),
    );
    await _refresh(); // a delete may have happened in the viewer
  }

  Future<void> _onQueryChanged(String value) async {
    final repo = _repository;
    setState(() => _query = value);
    if (value.trim().isEmpty) {
      // Empty query restores the full (sorted) list; no re-query needed.
      setState(() => _searchResults = const []);
      return;
    }
    if (repo == null) return;
    try {
      final results = await repo.searchDocuments(value);
      if (!mounted || value != _query) return; // race guard: newer query wins
      setState(() => _searchResults = results);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  // After returning from a push, re-apply search if active, else reload.
  Future<void> _refresh() => _searching ? _onQueryChanged(_query) : _load();

  void _onSortCriterion(SortCriterion c) =>
      setState(() => _sort = nextSort(_sort, c));

  void _onViewModeChanged(LibraryViewMode mode) =>
      setState(() => _viewMode = mode);

  Future<void> _renameDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    final newName = await showRenameDialog(
      context,
      s.document.name,
      suggest: widget.libraryDependencies.features.smartTitles
          ? () => repo.suggestTitleFor(s.document.id)
          : null,
    );
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

  Future<void> _moveDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    final result = await showMoveToFolderSheet(
      context,
      folders: _folders,
      onCreateFolder: (name) async {
        final f = await repo.createFolder(name);
        await _load();
        return f;
      },
    );
    if (result == null || !mounted) return;
    try {
      await repo.moveToFolder(s.document.id, result.folderId);
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't move document")));
    }
  }

  Future<void> _manageTags(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    // Fetch fresh rather than trust s.tags, so the sheet always seeds from
    // the current on-disk state (avoids staleness if s came from an older
    // snapshot of _summaries).
    final current = await repo.tagsForDocument(s.document.id);
    if (!mounted) return;
    final result = await showManageTagsSheet(
      context,
      tags: _tags,
      initial: current.map((t) => t.id).toSet(),
      onCreateTag: (name) async {
        final t = await repo.createTag(name);
        await _load();
        return t;
      },
    );
    if (result == null || !mounted) return;
    try {
      await repo.setDocumentTags(s.document.id, result);
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't update tags")));
    }
  }

  List<DocumentSummary> get _selectedDocuments =>
      _displayed.where((s) => _selectedIds.contains(s.document.id)).toList();

  Future<void> _bulkMove() async {
    final repo = _repository;
    if (repo == null) return;
    final selected = _selectedDocuments;
    if (selected.isEmpty) return;
    final result = await showMoveToFolderSheet(
      context,
      folders: _folders,
      onCreateFolder: (name) async {
        final f = await repo.createFolder(name);
        await _load();
        return f;
      },
    );
    if (result == null || !mounted) return;
    try {
      for (final s in selected) {
        await repo.moveToFolder(s.document.id, result.folderId);
      }
      if (mounted) _clearSelection();
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't move documents")));
    }
  }

  // Bulk tagging is a deliberate "set" (replace), not "add"/"merge": the
  // sheet is seeded with the INTERSECTION of every selected doc's current
  // tags (so pre-checked chips are tags common to all of them), and on Done
  // every selected doc's tag set is REPLACED with the exact chosen set. This
  // keeps the UI honest about what Done means (a reviewer should sanity-check
  // this is the desired product behavior — an "add tag to selection without
  // touching each doc's other tags" alternative was considered but produces a
  // sheet whose checked/unchecked chip state cannot represent a real per-doc
  // starting point when the selection's tags differ, which is confusing UX).
  Future<void> _bulkTag() async {
    final repo = _repository;
    if (repo == null) return;
    final selected = _selectedDocuments;
    if (selected.isEmpty) return;
    final tagSets = <Set<int>>[
      for (final s in selected)
        (await repo.tagsForDocument(s.document.id)).map((t) => t.id).toSet(),
    ];
    if (!mounted) return;
    final intersection = tagSets.isEmpty
        ? <int>{}
        : tagSets.reduce((a, b) => a.intersection(b));
    final result = await showManageTagsSheet(
      context,
      tags: _tags,
      initial: intersection,
      onCreateTag: (name) async {
        final t = await repo.createTag(name);
        await _load();
        return t;
      },
    );
    if (result == null || !mounted) return;
    try {
      for (final s in selected) {
        await repo.setDocumentTags(s.document.id, result);
      }
      if (mounted) _clearSelection();
      await _refresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't update tags")));
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
  // searching, else the active sort), further narrowed by the active folder
  // filter. Selection export follows this order.
  List<DocumentSummary> get _displayed {
    final base = _searching ? _searchResults : sortDocuments(_summaries, _sort);
    return base.where(_folderFilter.matches).where(_matchesTagFilter).toList();
  }

  // AND semantics: a document must carry every id in _activeTagIds.
  bool _matchesTagFilter(DocumentSummary s) =>
      _activeTagIds.isEmpty ||
      _activeTagIds.every((id) => s.tags.any((t) => t.id == id));

  Future<void> _openTagFilter() async {
    final result = await showTagFilterSheet(
      context,
      tags: _tags,
      initial: _activeTagIds,
    );
    if (result == null || !mounted) return;
    setState(() => _activeTagIds = result);
  }

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
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
            if (!_selectionMode) _buildActionRow(context),
          ],
        ),
      ),
      bottomNavigationBar: const DonationBanner(),
    );
  }

  // Whether the sort/view controls should show: a non-empty, loaded, non-error
  // library that isn't in selection mode and isn't in active search. During
  // search the list is in FTS relevance order and the sort pill is inert, so
  // it is hidden to avoid confusion.
  bool get _showControls =>
      !_loading &&
      !_error &&
      !_selectionMode &&
      !_searching &&
      _summaries.isNotEmpty;

  Widget _buildHeader(BuildContext context) {
    final r = context.ream;
    final overlay = Theme.of(context).brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: Colors.transparent,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: Colors.transparent,
          );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Container(
        color: r.paper,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _selectionMode
                ? _buildSelectionBar(context)
                : _buildTitleRow(context),
            if (!_selectionMode) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ReamSearchField(
                      controller: _searchController,
                      onChanged: _onQueryChanged,
                    ),
                  ),
                  if (widget.libraryDependencies.features.tags &&
                      _tags.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('tag-filter'),
                      tooltip: 'Filter by tag',
                      icon: Icon(
                        _activeTagIds.isEmpty
                            ? Icons.label_outline
                            : Icons.label,
                        color: r.ink2,
                      ),
                      onPressed: _openTagFilter,
                    ),
                  ],
                ],
              ),
            ],
            if (widget.libraryDependencies.features.folders &&
                _folders.isNotEmpty) ...[
              const SizedBox(height: 12),
              FolderFilterBar(
                folders: _folders,
                counts: _folderCounts(),
                active: _folderFilter,
                onChanged: (f) => setState(() => _folderFilter = f),
                onCreateFolder: _createFolder,
              ),
            ],
            if (_showControls) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SortPill(sort: _sort, onCriterionSelected: _onSortCriterion),
                  ReamSegmented<LibraryViewMode>(
                    key: const Key('library-view-toggle'),
                    value: _viewMode,
                    onChanged: _onViewModeChanged,
                    segments: const [
                      ReamSegment(value: LibraryViewMode.list, label: 'List'),
                      ReamSegment(value: LibraryViewMode.grid, label: 'Grid'),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    final r = context.ream;
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Documents', style: theme.textTheme.headlineMedium),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: r.muted),
                  const SizedBox(width: 6),
                  Text(
                    'Private · on this device',
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: r.muted,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        _buildSettingsMenu(context),
      ],
    );
  }

  Widget _buildSettingsMenu(BuildContext context) {
    final r = context.ream;
    return GestureDetector(
      key: const Key('home-settings'),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SettingsScreen(
            themeController: _themeController,
            feedbackDependencies: widget.feedbackDependencies,
            feedbackAvailable: _feedbackAvailable,
          ),
        ),
      ),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: r.surface,
          shape: BoxShape.circle,
          border: Border.all(color: r.line),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.settings_outlined, size: 18, color: r.ink2),
      ),
    );
  }

  Widget _buildSelectionBar(BuildContext context) {
    final r = context.ream;
    return Row(
      key: const Key('selection-bar'),
      children: [
        IconButton(
          key: const Key('selection-close'),
          tooltip: 'Cancel selection',
          icon: Icon(Icons.close, color: r.ink),
          onPressed: _clearSelection,
        ),
        Expanded(
          child: Text(
            '${_selectedIds.length} selected',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (widget.libraryDependencies.features.folders)
          IconButton(
            key: const Key('selection-move'),
            tooltip: 'Move to folder',
            icon: Icon(Icons.drive_file_move_outline, color: r.ink),
            onPressed: _bulkMove,
          ),
        if (widget.libraryDependencies.features.tags)
          IconButton(
            key: const Key('selection-tag'),
            tooltip: 'Tag',
            icon: Icon(Icons.label_outline, color: r.ink),
            onPressed: _bulkTag,
          ),
        IconButton(
          key: const Key('selection-export'),
          tooltip: 'Export',
          icon: Icon(Icons.ios_share, color: r.ink),
          onPressed: _exportSelected,
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final f = widget.libraryDependencies.features;
    final buttons = <Widget>[
      if (f.scan)
        Expanded(
          flex: 3,
          child: ReamActionButton(
            key: const Key('home-scan'),
            label: 'Scan',
            icon: Icons.add,
            primary: true,
            onPressed: _repository == null ? null : _openScan,
          ),
        ),
      if (f.idCard)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-scan-id'),
            label: 'ID card',
            icon: Icons.badge_outlined,
            onPressed: _repository == null ? null : _openIdScan,
          ),
        ),
      if (f.import)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-import'),
            label: 'Import',
            icon: Icons.download_outlined,
            onPressed: _repository == null ? null : _onImport,
          ),
        ),
    ];
    final spaced = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 8));
      spaced.add(buttons[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(children: spaced),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        key: Key('documents-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_error) return _buildError();

    if (_searching) {
      if (_searchResults.isEmpty) {
        return Center(
          key: const Key('documents-search-empty'),
          child: Text('No documents match "$_query".'),
        );
      }
      return _buildDocuments(_displayed);
    }

    if (_summaries.isEmpty) return const EmptyDocumentsView();
    return _buildDocuments(_displayed);
  }

  Widget _buildDocuments(List<DocumentSummary> docs) {
    if (_viewMode == LibraryViewMode.grid) {
      return DocumentsGridView(
        summaries: docs,
        onOpen: _openDocument,
        onRename: _renameDocument,
        onShare: _shareDocument,
        onMoveToFolder: _moveDocument,
        onManageTags: _manageTags,
        selectionMode: _selectionMode,
        selectedIds: _selectedIds,
        onToggleSelect: _toggleSelect,
        onLongPress: _startSelection,
        features: widget.libraryDependencies.features,
      );
    }
    return DocumentsListView(
      summaries: docs,
      onOpen: _openDocument,
      onRename: _renameDocument,
      onShare: _shareDocument,
      onMoveToFolder: _moveDocument,
      onManageTags: _manageTags,
      selectionMode: _selectionMode,
      selectedIds: _selectedIds,
      onToggleSelect: _toggleSelect,
      onLongPress: _startSelection,
      features: widget.libraryDependencies.features,
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
