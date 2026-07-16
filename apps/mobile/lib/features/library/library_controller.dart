import 'package:flutter/foundation.dart';

import 'document_repository.dart';
import 'document_sort.dart';
import 'document_summary.dart';
import 'library_dependencies.dart';
import 'selection_exporter.dart';

/// Owns the home library's state + orchestration (P06 tasks 9-11): repository
/// lifecycle + cold-start watchdog, the summaries list (sorted, cached off the
/// build path), FTS search with a newer-query-wins race guard, the active sort,
/// multi-select state, and the share/export policy. A [ChangeNotifier] (mirrors
/// SaveController) with a [_disposed] guard, unit-testable without a widget —
/// the HomeScreen widget keeps only navigation, dialogs, view mode, and the
/// theme/locale controllers.
class LibraryController extends ChangeNotifier {
  final LibraryDependencies _deps;
  final Duration _coldStartTimeout;

  LibraryController({
    required LibraryDependencies dependencies,
    required Duration coldStartStepTimeout,
  }) : _deps = dependencies,
       _coldStartTimeout = coldStartStepTimeout;

  DocumentRepository? _repository;
  DocumentRepository? get repository => _repository;
  late SelectionExporter _exporter;

  bool _loading = true;
  bool get loading => _loading;

  bool _error = false;
  bool get error => _error;

  // Set when a startup step failed/timed out, so the error screen can name the
  // stuck step (and it's logged for on-device diagnosis).
  String? _startupFailure;
  String? get startupFailure => _startupFailure;

  List<DocumentSummary> _summaries = const [];
  List<DocumentSummary> get summaries => _summaries;

  // The full list sorted by [_sort], cached so the whole-library sort runs only
  // when [_summaries]/[_sort] change — not on every unrelated rebuild.
  List<DocumentSummary> _sortedSummaries = const [];
  List<DocumentSummary> get sortedSummaries => _sortedSummaries;

  DocumentSort _sort = DocumentSort.initial;
  DocumentSort get sort => _sort;

  String _query = '';
  String get query => _query;
  bool get searching => _query.trim().isNotEmpty;

  // FTS results for the current non-empty query. Kept separate from [_summaries]
  // so clearing the query restores the full list without a re-query.
  List<DocumentSummary> _searchResults = const [];
  List<DocumentSummary> get searchResults => _searchResults;

  final Set<int> _selectedIds = <int>{};
  Set<int> get selectedIds => _selectedIds;
  bool get selectionMode => _selectedIds.isNotEmpty;

  bool _sharing = false;
  bool get sharing => _sharing;

  bool _disposed = false;

  /// The documents currently on screen, in display order (search relevance
  /// order when searching, else the active sort).
  List<DocumentSummary> get displayed =>
      searching ? _searchResults : _sortedSummaries;

  // --- lifecycle / watchdog ---

  Future<void> init() async {
    try {
      final repo = await _deps.createRepository().timeout(_coldStartTimeout);
      if (_disposed) return;
      _repository = repo;
      _exporter = SelectionExporter(
        repository: repo,
        share: _deps.share,
        archiver: _deps.archiver,
      );
      await load();
    } catch (e) {
      _failStartup('opening the library', e);
    }
  }

  Future<void> load() async {
    final repo = _repository;
    if (repo == null) return;
    try {
      final docs = await repo.listDocumentSummaries().timeout(
        _coldStartTimeout,
      );
      if (_disposed) return;
      _set(() {
        _summaries = docs;
        _sortedSummaries = sortDocuments(docs, _sort);
        _loading = false;
        _startupFailure = null;
      });
    } catch (e) {
      _failStartup('loading your documents', e);
    }
  }

  void _failStartup(String step, Object error) {
    // Always logged so a wedged cold start is diagnosable from device logs.
    _deps.logger().error(
      error,
      context: 'HomeScreen cold-start failed while $step',
    );
    if (_disposed) return;
    _set(() {
      _loading = false;
      _error = true;
      _startupFailure = 'Startup timed out while $step.';
    });
  }

  void retry() {
    _set(() {
      _error = false;
      _loading = true;
      _startupFailure = null;
    });
    // ignore: discarded_futures
    init();
  }

  /// After returning from a push, re-apply the active search else reload.
  Future<void> refresh() => searching ? onQueryChanged(_query) : load();

  // --- search / sort / selection ---

  Future<void> onQueryChanged(String value) async {
    _set(() => _query = value);
    if (value.trim().isEmpty) {
      // Empty query restores the full (sorted) list; no re-query needed.
      _set(() => _searchResults = const []);
      return;
    }
    final repo = _repository;
    if (repo == null) return;
    try {
      final results = await repo.searchDocuments(value);
      if (_disposed || value != _query) return; // race guard: newer query wins
      _set(() => _searchResults = results);
    } catch (_) {
      if (!_disposed) _set(() => _error = true);
    }
  }

  void setSortCriterion(SortCriterion c) => _set(() {
    _sort = nextSort(_sort, c);
    _sortedSummaries = sortDocuments(_summaries, _sort);
  });

  void toggleSelect(DocumentSummary s) => _set(() {
    final id = s.document.id;
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
  });

  void startSelection(DocumentSummary s) =>
      _set(() => _selectedIds.add(s.document.id));

  void clearSelection() => _set(_selectedIds.clear);

  // --- share / export (single-flight via the sharing flag) ---

  /// Shares one document's PDF. Returns true on success, false on FAILURE (the
  /// widget toasts), or null when it was a no-op (a share is already in flight).
  Future<bool?> shareDocument(DocumentSummary s) =>
      _guardedShare(() => _exporter.exportAndShare([s]));

  /// Exports the current multi-selection (zip-vs-pdf per [SelectionExporter])
  /// and clears the selection on success. Returns true/false/null as
  /// [shareDocument] (null = no-op: busy or nothing selected).
  Future<bool?> exportSelected() async {
    if (_sharing) return null;
    final selected = displayed
        .where((s) => _selectedIds.contains(s.document.id))
        .toList();
    if (selected.isEmpty) return null;
    final ok = await _guardedShare(() => _exporter.exportAndShare(selected));
    if (ok == true && !_disposed) clearSelection();
    return ok;
  }

  /// Runs [action] behind the single-flight sharing flag. null = refused (busy),
  /// true = success, false = failure.
  Future<bool?> _guardedShare(Future<void> Function() action) async {
    if (_sharing) return null;
    _set(() => _sharing = true);
    try {
      await action();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) _set(() => _sharing = false);
    }
  }

  /// Renames [documentId] then refreshes the list. Returns success.
  Future<bool> rename(int documentId, String newName) async {
    final repo = _repository;
    if (repo == null) return false;
    try {
      await repo.rename(documentId, newName);
      await refresh();
      return true;
    } catch (_) {
      return false;
    }
  }

  void _set(void Function() mutate) {
    if (_disposed) return;
    mutate();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
