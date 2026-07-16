import 'dart:async'; // unawaited
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile/l10n/l10n.dart';
import 'share_channel.dart';

import '../../core/ui/error_snack.dart';
import '../scan/scan_screen.dart';
import '../scan/scan_dependencies.dart';
import '../../theme/ream_theme.dart';
import 'crop_corners.dart';
import 'document_printer.dart';
import 'document_repository.dart';
import 'edit_crop_screen.dart';
import 'edit_filter_screen.dart';
import 'enhancer_mode.dart';
import 'feature_flags.dart';
import 'export/export_quality_dialog.dart';
import 'merge_picker_dialog.dart';
import 'page_image.dart';
import 'page_viewer_controller.dart';
import 'password_dialog.dart';
import 'pdf_preview_screen.dart';
import 'recognized_text_screen.dart';
import 'share/share_action.dart';
import 'view_state.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/editor_top_bar.dart';
import 'widgets/page_counter_pill.dart';
import 'widgets/page_thumbnail_strip.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/share_menu_button.dart';

/// Full-screen page viewer: pinch-zoom + pan over a document's page(s).
/// Multi-page-ready (PageView; one page today). All state + repository
/// orchestration lives in [PageViewerController] (P06); this widget is a thin
/// view — dialogs, navigation, l10n toasts, and rendering only — that drives
/// the controller through a `ListenableBuilder`.
///
/// The display image decodes at a bounded `cacheWidth` (screen × dpr ×
/// [_maxDisplayZoom]) rather than the full 12.5 MP capture — sharp up to full
/// pinch-zoom while avoiding the fit-to-screen full-res decode (P13). An edit
/// evicts only that page's cached image via [ImageCacheInvalidator] (scoped,
/// not a global clear).
class PageViewerScreen extends StatefulWidget {
  final int documentId;
  final String name;
  final DocumentRepository repository;
  final ScanDependencies dependencies;
  final DocumentPrinter printer;
  final ShareChannel share;
  final FeatureFlags features;
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
    this.dependencies = const ScanDependencies(),
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.features = const FeatureFlags(),
  });

  @override
  State<PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<PageViewerScreen> {
  final PageController _controller = PageController();
  late final PageViewerController _pvc;

  @override
  void initState() {
    super.initState();
    _pvc = PageViewerController(
      repository: widget.repository,
      documentId: widget.documentId,
      name: widget.name,
      printer: widget.printer,
      share: widget.share,
    );
    // ignore: discarded_futures
    _pvc.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _pvc.dispose();
    super.dispose();
  }

  Future<void> _exportPdf() async {
    final l10n = context.l10n;
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    final file = await _pvc.exportPdf(quality);
    if (!mounted) return;
    if (file == null) {
      context.showErrorSnack(l10n.viewerExportPdfError);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PdfPreviewScreen(
          pdfPath: file.path,
          name: _pvc.name,
          share: widget.share,
          features: widget.features,
        ),
      ),
    );
  }

  Future<void> _rename() async {
    final l10n = context.l10n;
    final newName = await showRenameDialog(context, _pvc.name);
    if (newName == null || !mounted) return;
    final ok = await _pvc.rename(newName);
    if (!ok && mounted) context.showErrorSnack(l10n.commonErrorRename);
  }

  Future<void> _confirmAndDelete() async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.viewerDeleteDocumentConfirm),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('page-viewer-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final deleted = await _pvc.deleteDocument();
    if (!mounted) return;
    if (deleted) {
      Navigator.of(
        context,
      ).pop(); // leave the viewer -> Home._load() reflects it
    } else {
      context.showErrorSnack(l10n.viewerDeleteDocumentError);
    }
  }

  Future<void> _confirmAndDeletePage() async {
    final l10n = context.l10n;
    final page = _pvc.currentPage;
    if (page == null) return;
    final isLast = _pvc.pages.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          isLast
              ? l10n.viewerDeletePageOnlyPageWarning
              : l10n.viewerDeletePageConfirm,
        ),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-page-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            key: const Key('page-viewer-delete-page-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final remaining = await _pvc.deletePage(page.position);
    if (!mounted) return;
    if (remaining == null) {
      context.showErrorSnack(l10n.viewerDeletePageError);
      return;
    }
    if (remaining == 0) {
      Navigator.of(context).pop(); // document gone → back to Home
      return;
    }
    // _pvc.deletePage reloaded + re-clamped current centrally.
    if (_controller.hasClients) _controller.jumpToPage(_pvc.current);
  }

  Future<void> _exportPageAsImage() async {
    final l10n = context.l10n;
    final page = _pvc.currentPage;
    if (page == null) return;
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    final ok = await _pvc.exportPageAsImageAndShare(page.position, quality);
    if (!ok && mounted) context.showErrorSnack(l10n.viewerShareImageError);
  }

  Future<void> _exportAllImages() async {
    final l10n = context.l10n;
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    final ok = await _pvc.exportAllImagesAndShare(quality);
    if (!ok && mounted) context.showErrorSnack(l10n.viewerShareImagesError);
  }

  Future<void> _print() async {
    final l10n = context.l10n;
    final ok = await _pvc.printDocument();
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.viewerPrintSuccess)));
    } else {
      context.showErrorSnack(l10n.viewerPrintError);
    }
  }

  Future<void> _protect() async {
    final l10n = context.l10n;
    final password = await showPasswordDialog(context);
    if (password == null || password.isEmpty || !mounted) return;
    final file = await _pvc.protect(password);
    if (!mounted) return;
    if (file != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.viewerProtectPdfSuccess)));
      unawaited(_pvc.shareQuietly(file));
    } else {
      context.showErrorSnack(l10n.viewerProtectPdfError);
    }
  }

  void _viewText() {
    final page = _pvc.currentPage;
    if (page == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecognizedTextScreen(
          documentId: widget.documentId,
          position: page.position,
          name: _pvc.name,
          initialText: page.ocrText,
          repository: widget.repository,
          share: widget.share,
        ),
      ),
    );
  }

  Future<void> _retakePage() async {
    final page = _pvc.currentPage;
    if (page == null || _pvc.editing) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(
          dependencies: widget.dependencies,
          repository: widget.repository,
          onCapture: (image, corners, enhancer) => _pvc.replacePage(
            page.position,
            image,
            corners: corners,
            enhancer: enhancer,
          ),
        ),
      ),
    );
    if (!mounted) return;
    await _pvc.reloadAfterEdit();
  }

  void _reorderPages(int oldIndex, int newIndex) {
    final messenger = ScaffoldMessenger.of(context);
    final errorText = context.l10n.viewerReorderPagesError;
    // ignore: discarded_futures
    unawaited(
      _pvc.reorder(oldIndex, newIndex).then((ok) {
        if (!ok && mounted) {
          messenger.showSnackBar(SnackBar(content: Text(errorText)));
        }
      }),
    );
  }

  Future<void> _rotatePage() async {
    final page = _pvc.currentPage;
    if (page == null || _pvc.editing) return;
    final err = context.l10n.viewerRotateError;
    final ok = await _pvc.rotatePage(page.position);
    if (!ok && mounted) context.showErrorSnack(err);
  }

  Future<void> _editCrop(PageImage pg) async {
    if (_pvc.editing) return;
    final l10n = context.l10n;
    final corners = await Navigator.of(context).push<CropCorners>(
      MaterialPageRoute<CropCorners>(
        builder: (_) => EditCropScreen(
          imagePath: pg.imagePath,
          initialCorners: pg.corners,
          quarterTurns: pg.rotationQuarterTurns,
        ),
      ),
    );
    if (corners == null || !mounted) return;
    final ok = await _pvc.updateCorners(pg.position, corners);
    if (!ok && mounted) context.showErrorSnack(l10n.viewerCropError);
  }

  Future<void> _editFilter(PageImage pg) async {
    if (_pvc.editing) return;
    final l10n = context.l10n;
    final mode = await Navigator.of(context).push<EnhancerMode>(
      MaterialPageRoute<EnhancerMode>(
        builder: (_) => EditFilterScreen(
          imagePath: pg.imagePath,
          initialMode: pg.enhancerMode,
        ),
      ),
    );
    if (mode == null || !mounted) return;
    final ok = await _pvc.updateEnhancer(pg.position, mode);
    if (!ok && mounted) context.showErrorSnack(l10n.viewerFilterError);
  }

  Future<void> _splitAfter() async {
    final l10n = context.l10n;
    final pages = _pvc.pages;
    if (pages.isEmpty) return;
    if (_pvc.current >= pages.length - 1) {
      context.showErrorSnack(l10n.viewerSplitLastPageWarning);
      return;
    }
    final page = pages[_pvc.current];
    final ok = await _pvc.splitAfter(page.position);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.viewerSplitSuccess)));
    } else {
      context.showErrorSnack(l10n.viewerSplitError);
    }
  }

  Future<void> _mergeAnother() async {
    final l10n = context.l10n;
    final sourceId = await showMergePicker(
      context,
      widget.repository,
      widget.documentId,
    );
    if (sourceId == null || !mounted) return;
    final ok = await _pvc.mergeInto(sourceId);
    if (!ok && mounted) context.showErrorSnack(l10n.viewerMergeError);
  }

  /// True when page-scoped actions (crop, share, delete-page, overflow…) should
  /// be disabled: while loading, in the error state, mid-export, mid-edit, or
  /// with no pages.
  bool get _actionsDisabled {
    final s = _pvc.state;
    return s is Loading ||
        s is ErrorState ||
        _pvc.exporting ||
        _pvc.editing ||
        _pvc.pages.isEmpty;
  }

  /// The Share toolbar button appears only when the umbrella `share` flag is on
  /// AND at least one share sub-action is enabled — so an empty share sheet can
  /// never be opened. Derived from the ShareAction list (P11), not a
  /// hand-maintained OR-chain, so a new share action can't drift out of sync.
  bool get _showShareButton => shouldShowShareButton(widget.features);

  /// The overflow (⋯) menu: Rename, Merge, Split, Delete-document. Returns null
  /// (no button) when every item is disabled by its feature flag.
  Widget? _buildOverflowMenu() {
    final f = widget.features;
    if (!(f.rename || f.merge || f.split || f.deleteDocument)) return null;
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      key: const Key('page-viewer-page-menu'),
      enabled: !_actionsDisabled,
      onSelected: (v) {
        if (v == 'rename') unawaited(_rename());
        if (v == 'merge') unawaited(_mergeAnother());
        if (v == 'split') unawaited(_splitAfter());
        if (v == 'delete') unawaited(_confirmAndDelete());
      },
      itemBuilder: (_) => [
        if (f.rename)
          PopupMenuItem<String>(
            value: 'rename',
            key: const Key('page-viewer-rename'),
            child: Text(l10n.commonRename),
          ),
        if (f.merge)
          PopupMenuItem<String>(
            value: 'merge',
            key: const Key('page-viewer-merge'),
            child: Text(l10n.viewerMenuMerge),
          ),
        if (f.split)
          PopupMenuItem<String>(
            value: 'split',
            key: const Key('page-viewer-split'),
            child: Text(l10n.viewerMenuSplit),
          ),
        if (f.deleteDocument)
          PopupMenuItem<String>(
            value: 'delete',
            key: const Key('page-viewer-delete'),
            child: Text(l10n.viewerMenuDeleteDocument),
          ),
      ],
    );
  }

  /// The share/export family, shown from the toolbar's Share action: Export PDF,
  /// Share as image, Share all as images, Print, Protect, plus the shared
  /// link/fax "extras". Rendered from the single [availableShareActions] list
  /// and dispatched by [ShareActionKind] (P11) — no per-item `if (features.x)`
  /// guards, no raw-string dispatch. Item keys/labels are unchanged, so the
  /// behavior tests only change which control opens the menu.
  Future<void> _openShareMenu() async {
    final l10n = context.l10n;
    final actions = availableShareActions(widget.features);
    final kind = await showModalBottomSheet<ShareActionKind>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final action in actions)
              ListTile(
                key: action.keyFor('page-viewer'),
                leading: Icon(action.icon),
                title: Text(action.label(l10n)),
                onTap: () => Navigator.of(ctx).pop(action.kind),
              ),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    switch (kind) {
      case ShareActionKind.exportPdf:
        await _exportPdf();
      case ShareActionKind.shareImage:
        await _exportPageAsImage();
      case ShareActionKind.exportAllImages:
        await _exportAllImages();
      case ShareActionKind.print:
        await _print();
      case ShareActionKind.protect:
        await _protect();
      case ShareActionKind.shareLink:
        if (mounted) handleShareExtra(context, kShareLinkValue);
      case ShareActionKind.fax:
        if (mounted) handleShareExtra(context, kFaxValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: ReamTheme.dark(),
        child: ListenableBuilder(
          listenable: _pvc,
          builder: (context, _) => Scaffold(
            appBar: EditorTopBar(
              title: _pvc.name,
              onBack: () => Navigator.of(context).pop(),
              trailing: _buildOverflowMenu(),
            ),
            body: Stack(
              children: [
                switch (_pvc.state) {
                  Loading() => const Center(
                    key: Key('page-viewer-loading'),
                    child: CircularProgressIndicator(),
                  ),
                  ErrorState() => _buildError(),
                  Empty() => _buildEmpty(),
                  Loaded(:final data) => _buildPages(data),
                },
                // Busy overlay while a mutating edit runs — blocks input and
                // signals progress so the user isn't left tapping a frozen UI.
                if (_pvc.editing)
                  const Positioned.fill(
                    child: ColoredBox(
                      color: Color(0x99000000),
                      child: Center(
                        key: Key('page-viewer-editing'),
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  ),
              ],
            ),
            bottomNavigationBar: EditorToolbar(
              showCrop: widget.features.crop,
              showRotate: widget.features.rotate,
              showFilter: widget.features.filter,
              showText: widget.features.viewText,
              showRetake: widget.features.retake,
              showShare: _showShareButton,
              showDelete: widget.features.deletePage,
              onCrop: _actionsDisabled
                  ? null
                  : () => _editCrop(_pvc.pages[_pvc.current]),
              onRotate: _actionsDisabled
                  ? null
                  : () => unawaited(_rotatePage()),
              onText: _actionsDisabled ? null : _viewText,
              onRetake: _actionsDisabled
                  ? null
                  : () => unawaited(_retakePage()),
              onShare: _actionsDisabled
                  ? null
                  : () => unawaited(_openShareMenu()),
              onDelete: _actionsDisabled
                  ? null
                  : () => unawaited(_confirmAndDeletePage()),
              onFilter: _actionsDisabled
                  ? null
                  : () => unawaited(_editFilter(_pvc.pages[_pvc.current])),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError() {
    final l10n = context.l10n;
    return Center(
      key: const Key('page-viewer-error'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.viewerLoadError),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('page-viewer-retry'),
            onPressed: () => unawaited(_pvc.load()),
            child: Text(l10n.commonRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() => Center(
    key: const Key('page-viewer-empty'),
    child: Text(context.l10n.viewerEmptyPages),
  );

  // Max pinch-zoom. The display image is decoded at `screen×dpr×_maxDisplayZoom`
  // (below), so it stays sharp up to full zoom while NOT decoding the whole
  // 12.5 MP capture for the fit-to-screen view (P13 full-res-decode).
  static const double _maxDisplayZoom = 2.5;

  Widget _buildPages(List<PageImage> pages) {
    final mq = MediaQuery.of(context);
    // Bound the decode to what max-zoom actually needs (memory) while keeping
    // zoom sharp. cacheWidth > the source is a no-op, so small flats decode
    // native.
    final cacheWidth = (mq.size.width * mq.devicePixelRatio * _maxDisplayZoom)
        .round();
    // Hand the width to the controller so a scoped evict on the next edit
    // targets the exact ResizeImage variant (P13 task 1/2).
    _pvc.displayCacheWidth = cacheWidth;
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: _pvc.setCurrent,
                itemBuilder: (context, i) {
                  final pg = pages[i];
                  return InteractiveViewer(
                    key: Key('page-viewer-page-${pg.position}'),
                    maxScale: _maxDisplayZoom,
                    child: Image.file(
                      File(pg.displayPath),
                      // Key includes the edit epoch so a same-path regenerated
                      // flat forces a fresh decode instead of showing stale.
                      key: ValueKey('${pg.displayPath}#${_pvc.imageEpoch}'),
                      cacheWidth: cacheWidth,
                      fit: BoxFit.contain,
                      errorBuilder: (c, e, s) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 64),
                      ),
                    ),
                  );
                },
              ),
              if (pages.length > 1)
                Positioned(
                  top: 12,
                  right: 12,
                  child: PageCounterPill(
                    key: const Key('page-viewer-page-counter'),
                    current: _pvc.current + 1,
                    total: pages.length,
                  ),
                ),
            ],
          ),
        ),
        PageThumbnailStrip(
          pages: pages,
          currentIndex: _pvc.current,
          onTap: (i) => _controller.animateToPage(
            i,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          ),
          onReorder: _reorderPages,
        ),
      ],
    );
  }
}
