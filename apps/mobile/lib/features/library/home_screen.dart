import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../scan/capture_review_screen.dart';
import '../scan/captured_image.dart';
import '../scan/id_scan_screen.dart';
import '../scan/scan_screen.dart';
import '../scan/scan_dependencies.dart';
import '../../core/ui/error_snack.dart';
import '../../l10n/l10n.dart';
import '../../l10n/locale_controller.dart';
import '../../l10n/locale_store.dart';
import '../../theme/ream_colors.dart';
import '../../theme/theme_controller.dart';
import '../../theme/theme_mode_store.dart';
import '../../theme/widgets/ream_action_button.dart';
import '../../theme/widgets/ream_search_field.dart';
import '../../theme/widgets/ream_segmented.dart';
import 'document_summary.dart';
import 'library_controller.dart';
import 'library_dependencies.dart';
import 'library_view_mode.dart';
import 'page_viewer_screen.dart';
import 'save_controller.dart';
import 'widgets/documents_grid_view.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/sort_pill.dart';
import '../donation/donation_banner.dart';
import '../donation/donation_availability.dart';
import '../feedback/feedback_dependencies.dart';
import '../settings/settings_screen.dart';

/// The app's home: the document library. All library state + orchestration lives
/// in [LibraryController] (P06); this widget keeps navigation, dialogs, the
/// view-mode toggle, and the injected theme/locale controllers, and drives the
/// controller through a `ListenableBuilder`.
class HomeScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final LibraryDependencies libraryDependencies;
  final FeedbackDependencies feedbackDependencies;
  final ThemeController? themeController;
  final LocaleController? localeController;

  const HomeScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
    this.feedbackDependencies = const FeedbackDependencies(),
    this.themeController,
    this.localeController,
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
  late final LibraryController _lib = LibraryController(
    dependencies: widget.libraryDependencies,
    coldStartStepTimeout: HomeScreen.coldStartStepTimeout,
  );

  bool _feedbackAvailable = false;
  LibraryViewMode _viewMode = LibraryViewMode.list;

  // Own (and therefore dispose) a controller ONLY when we constructed the
  // fallback; an injected controller is the caller's to dispose (P06 task 4).
  late final bool _ownsThemeController = widget.themeController == null;
  late final ThemeController _themeController =
      widget.themeController ??
      ThemeController(store: InMemoryThemeModeStore());
  late final bool _ownsLocaleController = widget.localeController == null;
  late final LocaleController _localeController =
      widget.localeController ?? LocaleController(store: InMemoryLocaleStore());

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // ignore: discarded_futures
    _lib.init();
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
    _lib.dispose();
    // Dispose only the controllers WE created (P06 task 4) — never an injected
    // one, which the caller still owns and may reuse.
    if (_ownsThemeController) _themeController.dispose();
    if (_ownsLocaleController) _localeController.dispose();
    super.dispose();
  }

  Future<void> _openScan() async {
    final repo = _lib.repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ScanScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _lib.refresh(); // a save may have happened while we were away
  }

  Future<void> _openIdScan() async {
    final repo = _lib.repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            IdScanScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _lib.refresh();
  }

  Future<void> _onImport() async {
    final repo = _lib.repository;
    if (repo == null) return;
    final messenger = ScaffoldMessenger.of(context);
    CapturedImage? image;
    try {
      image = await widget.dependencies.createGalleryPicker().pick();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(context.l10n.homeErrorImportPhoto)),
      );
      return;
    }
    if (image == null) return; // user cancelled
    if (!mounted) return;

    final capturedImage = image;
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
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
                  SnackBar(content: Text(l10n.commonErrorSaveDocument)),
                );
                return;
              }
              navigator.pop();
              await _lib.refresh();
            },
          ),
        ),
      ),
    );
    saveController.dispose();
  }

  Future<void> _openDocument(DocumentSummary s) async {
    final repo = _lib.repository;
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
    await _lib.refresh(); // a delete may have happened in the viewer
  }

  Future<void> _renameDocument(DocumentSummary s) async {
    final newName = await showRenameDialog(context, s.document.name);
    if (newName == null || !mounted) return;
    final l10n = context.l10n;
    final ok = await _lib.rename(s.document.id, newName);
    if (!ok && mounted) context.showErrorSnack(l10n.commonErrorRename);
  }

  Future<void> _shareDocument(DocumentSummary s) async {
    final l10n = context.l10n;
    final result = await _lib.shareDocument(s);
    if (result == false && mounted)
      context.showErrorSnack(l10n.commonErrorShare);
  }

  Future<void> _exportSelected() async {
    final l10n = context.l10n;
    final result = await _lib.exportSelected();
    if (result == false && mounted)
      context.showErrorSnack(l10n.commonErrorShare);
  }

  void _onViewModeChanged(LibraryViewMode mode) =>
      setState(() => _viewMode = mode);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _lib,
      builder: (context, _) {
        // The banner's own SafeArea absorbs the bottom inset when shown; without
        // it (iOS, guideline 3.1.1) the body must clear the home indicator.
        final banner = donationsAvailable ? const DonationBanner() : null;
        return Scaffold(
          body: Stack(
            children: [
              SafeArea(
                bottom: banner == null,
                child: Column(
                  children: [
                    _buildHeader(context),
                    Expanded(child: _buildBody()),
                    if (!_lib.selectionMode) _buildActionRow(context),
                  ],
                ),
              ),
              // Busy overlay while a share/export runs — blocks input and signals
              // progress so the user isn't left tapping a frozen UI.
              if (_lib.sharing)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                    child: Center(
                      key: Key('home-sharing'),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: banner,
        );
      },
    );
  }

  // Whether the sort/view controls should show: a non-empty, loaded, non-error
  // library that isn't in selection mode and isn't in active search. During
  // search the list is in FTS relevance order and the sort pill is inert, so
  // it is hidden to avoid confusion.
  bool get _showControls =>
      !_lib.loading &&
      !_lib.error &&
      !_lib.selectionMode &&
      !_lib.searching &&
      _lib.summaries.isNotEmpty;

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
            _lib.selectionMode
                ? _buildSelectionBar(context)
                : _buildTitleRow(context),
            if (!_lib.selectionMode) ...[
              const SizedBox(height: 14),
              ReamSearchField(
                controller: _searchController,
                onChanged: _lib.onQueryChanged,
              ),
            ],
            if (_showControls) ...[
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SortPill(
                    sort: _lib.sort,
                    onCriterionSelected: _lib.setSortCriterion,
                  ),
                  ReamSegmented<LibraryViewMode>(
                    key: const Key('library-view-toggle'),
                    value: _viewMode,
                    onChanged: _onViewModeChanged,
                    segments: [
                      ReamSegment(
                        value: LibraryViewMode.list,
                        label: context.l10n.homeViewList,
                      ),
                      ReamSegment(
                        value: LibraryViewMode.grid,
                        label: context.l10n.homeViewGrid,
                      ),
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
              Text(
                context.l10n.homeDocumentsTitle,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_outline, size: 12, color: r.muted),
                  const SizedBox(width: 6),
                  Text(
                    context.l10n.homePrivateOnDevice,
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
            localeController: _localeController,
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
          tooltip: context.l10n.homeCancelSelectionTooltip,
          icon: Icon(Icons.close, color: r.ink),
          onPressed: _lib.clearSelection,
        ),
        Expanded(
          child: Text(
            context.l10n.homeSelectedCount(_lib.selectedIds.length),
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          key: const Key('selection-export'),
          tooltip: context.l10n.homeExportTooltip,
          icon: Icon(Icons.ios_share, color: r.ink),
          // Disabled while a share/export is already in flight — the re-entry
          // guard is now visibly disabled instead of silently swallowing taps.
          onPressed: _lib.sharing ? null : _exportSelected,
        ),
      ],
    );
  }

  Widget _buildActionRow(BuildContext context) {
    final f = widget.libraryDependencies.features;
    final ready = _lib.repository != null;
    final buttons = <Widget>[
      if (f.scan)
        Expanded(
          flex: 3,
          child: ReamActionButton(
            key: const Key('home-scan'),
            label: context.l10n.homeActionScan,
            icon: Icons.add,
            primary: true,
            onPressed: ready ? _openScan : null,
          ),
        ),
      if (f.idCard)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-scan-id'),
            label: context.l10n.homeActionIdCard,
            icon: Icons.badge_outlined,
            onPressed: ready ? _openIdScan : null,
          ),
        ),
      if (f.import)
        Expanded(
          flex: 2,
          child: ReamActionButton(
            key: const Key('home-import'),
            label: context.l10n.homeActionImport,
            icon: Icons.download_outlined,
            onPressed: ready ? _onImport : null,
          ),
        ),
    ];
    final spaced = <Widget>[];
    for (var i = 0; i < buttons.length; i++) {
      if (i > 0) spaced.add(const SizedBox(width: 8));
      spaced.add(buttons[i]);
    }
    // With the donation banner below, 8px suffices (the banner adds its own
    // height); without it this padding is all that separates the row from the
    // screen edge on inset-less devices, so keep a real gap.
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, donationsAvailable ? 8 : 16),
      child: Row(children: spaced),
    );
  }

  Widget _buildBody() {
    if (_lib.loading) {
      return const Center(
        key: Key('documents-loading'),
        child: CircularProgressIndicator(),
      );
    }
    if (_lib.error) return _buildError();

    if (_lib.searching) {
      if (_lib.searchResults.isEmpty) {
        return Center(
          key: const Key('documents-search-empty'),
          child: Text(context.l10n.homeSearchNoMatch(_lib.query)),
        );
      }
      return _buildDocuments(_lib.searchResults);
    }

    if (_lib.summaries.isEmpty) return const EmptyDocumentsView();
    return _buildDocuments(_lib.sortedSummaries);
  }

  Widget _buildDocuments(List<DocumentSummary> docs) {
    if (_viewMode == LibraryViewMode.grid) {
      return DocumentsGridView(
        summaries: docs,
        onOpen: _openDocument,
        onRename: _renameDocument,
        onShare: _shareDocument,
        selectionMode: _lib.selectionMode,
        selectedIds: _lib.selectedIds,
        onToggleSelect: _lib.toggleSelect,
        onLongPress: _lib.startSelection,
      );
    }
    return DocumentsListView(
      summaries: docs,
      onOpen: _openDocument,
      onRename: _renameDocument,
      onShare: _shareDocument,
      selectionMode: _lib.selectionMode,
      selectedIds: _lib.selectedIds,
      onToggleSelect: _lib.toggleSelect,
      onLongPress: _lib.startSelection,
      features: widget.libraryDependencies.features,
    );
  }

  Widget _buildError() {
    return Center(
      key: const Key('documents-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_lib.startupFailure ?? context.l10n.homeErrorLoadDocuments),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('documents-retry'),
            onPressed: _lib.retry,
            child: Text(context.l10n.commonRetry),
          ),
        ],
      ),
    );
  }
}
