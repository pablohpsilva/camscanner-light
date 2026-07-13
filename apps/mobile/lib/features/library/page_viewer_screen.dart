import 'dart:async'; // unawaited
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'share_channel.dart';

import '../scan/scan_screen.dart';
import '../scan/scan_dependencies.dart';
import '../../theme/ream_theme.dart';
import 'crop_corners.dart';
import 'document_printer.dart';
import 'document_repository.dart';
import 'edit_crop_screen.dart';
import 'export/export_quality_dialog.dart';
import 'merge_picker_dialog.dart';
import 'page_image.dart';
import 'password_dialog.dart';
import 'pdf_preview_screen.dart';
import 'recognized_text_screen.dart';
import 'widgets/editor_toolbar.dart';
import 'widgets/editor_top_bar.dart';
import 'widgets/page_counter_pill.dart';
import 'widgets/page_thumbnail_strip.dart';
import 'widgets/rename_dialog.dart';
import 'widgets/share_menu_button.dart';

/// Full-screen page viewer: pinch-zoom + pan over a document's page(s).
/// Multi-page-ready (PageView; one page today). Loads pages on init and shows
/// loading / error+retry / empty / loaded. The delete action confirms, deletes
/// (row + files), and pops back to the list. The SCREEN owns the delete
/// sequence; the dialog only returns the user's choice.
///
/// Decodes full-resolution (no cacheWidth) so zoom is usable — its Image is a
/// FileImage, NOT a ResizeImage. NOTE: this is not memory-safe for many pages;
/// when multi-page capture lands, add decode management (screen-width cacheWidth
/// + offscreen dispose).
class PageViewerScreen extends StatefulWidget {
  final int documentId;
  final String name;
  final DocumentRepository repository;
  final ScanDependencies dependencies;
  final DocumentPrinter printer;
  final ShareChannel share;
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
    this.dependencies = const ScanDependencies(),
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
  });

  @override
  State<PageViewerScreen> createState() => _PageViewerScreenState();
}

class _PageViewerScreenState extends State<PageViewerScreen> {
  final PageController _controller = PageController();
  List<PageImage>? _pages;
  bool _loading = true;
  bool _error = false;
  bool _exporting = false;
  // True while a mutating edit (rotate/crop/retake) is running. Edits are
  // single-flight: the toolbar is disabled and re-entry is refused so
  // overlapping full-res regenerations can't race (which made the image
  // appear to "revert" — 4x90 = 360).
  bool _editing = false;
  // Bumped on every edit so the displayed Image gets a new key and is forced
  // to re-decode. A regenerated flat reuses its file PATH, and FileImage is
  // keyed by path — so clearing the image cache alone leaves the mounted Image
  // element showing its already-decoded (stale) frame. The changing key
  // recreates the element, which (with the cache cleared) reads fresh bytes.
  int _imageEpoch = 0;
  int _current = 0;
  late String _name;

  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final pages = await widget.repository.getDocumentPages(widget.documentId);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  Future<void> _reloadAfterEdit() async {
    // The regenerated flat reuses its file path; FileImage caches by path, so
    // clear the cache before reloading or the stale image would show.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    _imageEpoch++; // force the displayed Image to re-decode (see field doc)
    if (!mounted) return;
    await _load();
  }

  Future<void> _exportPdf() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = await widget.repository.exportPdf(
        widget.documentId,
        quality: quality,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
            pdfPath: file.path,
            name: _name,
            share: widget.share,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't export PDF")));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _rename() async {
    final newName = await showRenameDialog(context, _name);
    if (newName == null) return;
    if (!mounted) return;
    try {
      final updated = await widget.repository.rename(
        widget.documentId,
        newName,
      );
      if (!mounted) return;
      setState(() => _name = updated.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't rename")));
    }
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: const Text("Delete this document? This can't be undone."),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('page-viewer-delete-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repository.deleteDocument(widget.documentId);
      if (!mounted) return;
      Navigator.of(
        context,
      ).pop(); // leave the viewer -> Home._load() reflects it
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't delete")));
    }
  }

  Future<void> _confirmAndDeletePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    final isLast = pages.length == 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(
          isLast
              ? 'This is the only page. Deleting it removes the whole document.'
              : "Delete this page? This can't be undone.",
        ),
        actions: [
          TextButton(
            key: const Key('page-viewer-delete-page-cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('page-viewer-delete-page-confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final remaining = await widget.repository.deletePage(
        widget.documentId,
        page.position,
      );
      if (!mounted) return;
      if (remaining == 0) {
        Navigator.of(context).pop(); // document gone → back to Home
        return;
      }
      if (_current >= remaining) _current = remaining - 1; // clamp
      await _load();
      if (mounted && _controller.hasClients) _controller.jumpToPage(_current);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't delete page")));
    }
  }

  Future<void> _exportPageAsImage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file = await widget.repository.exportPageAsImage(
        widget.documentId,
        page.position,
        quality: quality,
      );
      await widget.share.share([file.path], subject: _name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share image")));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAllImages() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final files = await widget.repository.exportAllPagesAsImages(
        widget.documentId,
        quality: quality,
      );
      await widget.share.share(
        files.map((f) => f.path).toList(),
        subject: _name,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't share images")));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _print() async {
    try {
      final file = await widget.repository.exportPdf(widget.documentId);
      await widget.printer.printPdf(file, name: _name);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sent to printer')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't print")));
    }
  }

  Future<void> _protect() async {
    final password = await showPasswordDialog(context);
    if (password == null || password.isEmpty || !mounted) return;
    try {
      final file = await widget.repository.exportProtectedPdf(
        widget.documentId,
        password,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Protected PDF ready')));
      unawaited(_shareQuietly(file));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't protect PDF")));
    }
  }

  Future<void> _shareQuietly(File file) async {
    try {
      await widget.share.share([file.path], subject: _name);
    } catch (_) {
      /* share unavailable (e.g. host test) — ignore */
    }
  }

  void _viewText() {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecognizedTextScreen(
          documentId: widget.documentId,
          position: page.position,
          name: _name,
          initialText: page.ocrText,
          repository: widget.repository,
          share: widget.share,
        ),
      ),
    );
  }

  Future<void> _retakePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty || _editing) return;
    final page = pages[_current];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScanScreen(
          dependencies: widget.dependencies,
          repository: widget.repository,
          onCapture: (image, corners, enhancer) async {
            try {
              await widget.repository.replacePage(
                widget.documentId,
                page.position,
                image,
                corners: corners,
                enhancer: enhancer,
              );
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await _reloadAfterEdit();
  }

  void _reorderPages(int oldIndex, int newIndex) {
    // onReorderItem (used in PageThumbnailStrip) provides newIndex as the
    // correct insertion index already — no adjustment needed.
    final ordered = List<PageImage>.from(_pages!);
    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    setState(() => _pages = ordered);
    // ignore: discarded_futures
    _persistReorder(ordered);
  }

  Future<void> _persistReorder(List<PageImage> ordered) async {
    try {
      await widget.repository.reorderPages(
        widget.documentId,
        ordered.map((p) => p.position).toList(),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't reorder pages")));
      _load();
    }
  }

  /// Runs a single mutating edit with single-flight protection: refuses
  /// re-entry while another edit is running, flips [_editing] (which disables
  /// the toolbar + shows a busy overlay), reloads on success, and surfaces
  /// [failMessage] on failure. Callers do their own navigation (e.g. opening
  /// the crop editor) BEFORE calling this with the resolved edit closure.
  Future<void> _runEdit(
    Future<void> Function() edit,
    String failMessage,
  ) async {
    if (_editing) return; // single-flight
    setState(() => _editing = true);
    try {
      await edit();
      if (!mounted) return;
      await _reloadAfterEdit();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failMessage)));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _rotatePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty || _editing) return;
    final page = pages[_current];
    await _runEdit(
      () => widget.repository.rotatePage(widget.documentId, page.position),
      "Couldn't rotate",
    );
  }

  Future<void> _editCrop(PageImage pg) async {
    if (_editing) return;
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
    await _runEdit(
      () => widget.repository.updatePageCorners(
        widget.documentId,
        pg.position,
        corners,
      ),
      "Couldn't update crop",
    );
  }

  Future<void> _splitAfter() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    if (_current >= pages.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('This is the last page — nothing to split after.'),
        ),
      );
      return;
    }
    final page = pages[_current];
    try {
      await widget.repository.splitAfter(widget.documentId, page.position);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Split into a new document')),
      );
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't split")));
    }
  }

  Future<void> _mergeAnother() async {
    final sourceId = await showMergePicker(
      context,
      widget.repository,
      widget.documentId,
    );
    if (sourceId == null || !mounted) return;
    try {
      await widget.repository.mergeInto(widget.documentId, sourceId);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't merge")));
    }
  }

  /// True when page-scoped actions (crop, share, delete-page, overflow…) should
  /// be disabled: while loading, in the error state, mid-export, or with no
  /// pages. Mirrors the guard the old AppBar controls used.
  bool get _actionsDisabled =>
      _loading || _error || _exporting || _editing || (_pages?.isEmpty ?? true);

  /// The overflow (⋯) menu: Rename, Merge, Split, Delete-document.
  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      key: const Key('page-viewer-page-menu'),
      enabled: !_actionsDisabled,
      onSelected: (v) {
        if (v == 'rename') unawaited(_rename());
        if (v == 'merge') unawaited(_mergeAnother());
        if (v == 'split') unawaited(_splitAfter());
        if (v == 'delete') unawaited(_confirmAndDelete());
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'rename',
          key: Key('page-viewer-rename'),
          child: Text('Rename'),
        ),
        PopupMenuItem<String>(
          value: 'merge',
          key: Key('page-viewer-merge'),
          child: Text('Merge another document…'),
        ),
        PopupMenuItem<String>(
          value: 'split',
          key: Key('page-viewer-split'),
          child: Text('Split after this page'),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          key: Key('page-viewer-delete'),
          child: Text('Delete document'),
        ),
      ],
    );
  }

  /// The share/export family, shown from the toolbar's Share action: Export PDF,
  /// Share as image, Share all as images, Print, Protect, plus the shared
  /// link/fax "extras". Item keys match the old overflow menu so behavior tests
  /// only change which control opens the menu.
  Future<void> _openShareMenu() async {
    final value = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('page-viewer-export'),
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Export PDF'),
              onTap: () => Navigator.of(ctx).pop('export-pdf'),
            ),
            ListTile(
              key: const Key('page-viewer-export-image'),
              leading: const Icon(Icons.image_outlined),
              title: const Text('Share as image'),
              onTap: () => Navigator.of(ctx).pop('export-image'),
            ),
            ListTile(
              key: const Key('page-viewer-export-all-images'),
              leading: const Icon(Icons.collections_outlined),
              title: const Text('Share all as images'),
              onTap: () => Navigator.of(ctx).pop('export-all-images'),
            ),
            ListTile(
              key: const Key('page-viewer-print'),
              leading: const Icon(Icons.print_outlined),
              title: const Text('Print'),
              onTap: () => Navigator.of(ctx).pop('print'),
            ),
            ListTile(
              key: const Key('page-viewer-protect'),
              leading: const Icon(Icons.lock_outline),
              title: const Text('Protect with password'),
              onTap: () => Navigator.of(ctx).pop('protect'),
            ),
            ListTile(
              key: const Key('page-viewer-share-link'),
              leading: const Icon(Icons.link),
              title: const Text('Share link'),
              onTap: () => Navigator.of(ctx).pop(kShareLinkValue),
            ),
            ListTile(
              key: const Key('page-viewer-fax'),
              leading: const Icon(Icons.print),
              title: const Text('Fax'),
              onTap: () => Navigator.of(ctx).pop(kFaxValue),
            ),
          ],
        ),
      ),
    );
    if (value == null || !mounted) return;
    switch (value) {
      case 'export-pdf':
        await _exportPdf();
      case 'export-image':
        await _exportPageAsImage();
      case 'export-all-images':
        await _exportAllImages();
      case 'print':
        await _print();
      case 'protect':
        await _protect();
      case kShareLinkValue:
      case kFaxValue:
        if (mounted) handleShareExtra(context, value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages;
    final hasPages = pages != null && pages.isNotEmpty;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: ReamTheme.dark(),
        child: Scaffold(
          appBar: EditorTopBar(
            title: _name,
            onBack: () => Navigator.of(context).pop(),
            trailing: _buildOverflowMenu(),
          ),
          body: Stack(
            children: [
              _loading
                  ? const Center(
                      key: Key('page-viewer-loading'),
                      child: CircularProgressIndicator(),
                    )
                  : _error
                  ? _buildError()
                  : !hasPages
                  ? _buildEmpty()
                  : _buildPages(pages),
              // Busy overlay while a mutating edit runs — blocks input and
              // signals progress so the user isn't left tapping a frozen UI.
              if (_editing)
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
            onCrop: _actionsDisabled
                ? null
                : () => _editCrop(_pages![_current]),
            onRotate: _actionsDisabled ? null : () => unawaited(_rotatePage()),
            onText: _actionsDisabled ? null : _viewText,
            onRetake: _actionsDisabled ? null : () => unawaited(_retakePage()),
            onShare: _actionsDisabled
                ? null
                : () => unawaited(_openShareMenu()),
            onDelete: _actionsDisabled
                ? null
                : () => unawaited(_confirmAndDeletePage()),
          ),
        ),
      ),
    );
  }

  Widget _buildError() => Center(
    key: const Key('page-viewer-error'),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text("Couldn't load this document."),
        const SizedBox(height: 8),
        FilledButton(
          key: const Key('page-viewer-retry'),
          onPressed: _load,
          child: const Text('Retry'),
        ),
      ],
    ),
  );

  Widget _buildEmpty() => const Center(
    key: Key('page-viewer-empty'),
    child: Text('This document has no pages.'),
  );

  Widget _buildPages(List<PageImage> pages) {
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _current = i),
                itemBuilder: (context, i) {
                  final pg = pages[i];
                  return InteractiveViewer(
                    key: Key('page-viewer-page-${pg.position}'),
                    child: Image.file(
                      File(pg.displayPath),
                      // Key includes the edit epoch so a same-path regenerated
                      // flat forces a fresh decode instead of showing stale.
                      key: ValueKey('${pg.displayPath}#$_imageEpoch'),
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
                    current: _current + 1,
                    total: pages.length,
                  ),
                ),
            ],
          ),
        ),
        PageThumbnailStrip(
          pages: pages,
          currentIndex: _current,
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
