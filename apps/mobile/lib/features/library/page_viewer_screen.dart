import 'dart:async'; // unawaited
import 'dart:io';

import 'package:flutter/material.dart';
import 'share_channel.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
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
import 'widgets/page_thumbnail_strip.dart';
import 'widgets/rename_dialog.dart';

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

  Future<void> _exportPdf() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final file =
          await widget.repository.exportPdf(widget.documentId, quality: quality);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PdfPreviewScreen(
              pdfPath: file.path, name: _name, share: widget.share),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export PDF")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _rename() async {
    final newName = await showRenameDialog(context, _name);
    if (newName == null) return;
    if (!mounted) return;
    try {
      final updated = await widget.repository.rename(widget.documentId, newName);
      if (!mounted) return;
      setState(() => _name = updated.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rename")),
      );
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
      Navigator.of(context).pop(); // leave the viewer -> Home._load() reflects it
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete")),
      );
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
        content: Text(isLast
            ? 'This is the only page. Deleting it removes the whole document.'
            : "Delete this page? This can't be undone."),
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
      final remaining =
          await widget.repository.deletePage(widget.documentId, page.position);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't delete page")),
      );
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
      await widget.repository
          .exportPageAsImage(widget.documentId, page.position, quality: quality);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Page saved as image')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export image")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportAllImages() async {
    final quality = await showExportQualityDialog(context);
    if (quality == null || !mounted) return;
    setState(() => _exporting = true);
    try {
      final files = await widget.repository
          .exportAllPagesAsImages(widget.documentId, quality: quality);
      if (!mounted) return;
      final n = files.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $n ${n == 1 ? 'image' : 'images'}')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't export images")),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _print() async {
    try {
      final file = await widget.repository.exportPdf(widget.documentId);
      await widget.printer.printPdf(file, name: _name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to printer')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't print")),
      );
    }
  }

  Future<void> _protect() async {
    final password = await showPasswordDialog(context);
    if (password == null || password.isEmpty || !mounted) return;
    try {
      final file =
          await widget.repository.exportProtectedPdf(widget.documentId, password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Protected PDF ready')),
      );
      unawaited(_shareQuietly(file));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't protect PDF")),
      );
    }
  }

  Future<void> _shareQuietly(File file) async {
    try {
      await widget.share.share([file.path], subject: _name);
    } catch (_) {/* share unavailable (e.g. host test) — ignore */}
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
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CameraScreen(
          dependencies: widget.dependencies,
          repository: widget.repository,
          onCapture: (image, corners, enhancer) async {
            try {
              await widget.repository.replacePage(
                  widget.documentId, page.position, image,
                  corners: corners, enhancer: enhancer);
              return true;
            } catch (_) {
              return false;
            }
          },
        ),
      ),
    );
    if (!mounted) return;
    await _load();
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
          widget.documentId, ordered.map((p) => p.position).toList());
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reorder pages")),
      );
      _load();
    }
  }

  Future<void> _rotatePage() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    final page = pages[_current];
    try {
      await widget.repository.rotatePage(widget.documentId, page.position);
      // FileImage caches by path; the rotated bytes reuse the flat path, so
      // clear the cache before reloading or the stale image would show.
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rotate")),
      );
    }
  }

  Future<void> _editCrop(PageImage pg) async {
    final corners = await Navigator.of(context).push<CropCorners>(
      MaterialPageRoute<CropCorners>(
        builder: (_) => EditCropScreen(
          imagePath: pg.imagePath,
          initialCorners: pg.corners,
        ),
      ),
    );
    if (corners == null || !mounted) return;
    try {
      await widget.repository.updatePageCorners(
          widget.documentId, pg.position, corners);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't update crop")),
      );
    }
  }

  Future<void> _splitAfter() async {
    final pages = _pages;
    if (pages == null || pages.isEmpty) return;
    if (_current >= pages.length - 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This is the last page — nothing to split after.')),
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't split")),
      );
    }
  }

  Future<void> _mergeAnother() async {
    final sourceId =
        await showMergePicker(context, widget.repository, widget.documentId);
    if (sourceId == null || !mounted) return;
    try {
      await widget.repository.mergeInto(widget.documentId, sourceId);
      if (!mounted) return;
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't merge")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_name),
        actions: [
          IconButton(
            key: const Key('page-viewer-rename'),
            tooltip: 'Rename',
            icon: const Icon(Icons.edit_outlined),
            onPressed:
                (_loading || _error || _exporting) ? null : _rename,
          ),
          IconButton(
            key: const Key('page-viewer-edit'),
            tooltip: 'Edit crop',
            icon: const Icon(Icons.crop),
            onPressed: (_loading || _error || _exporting ||
                    (_pages?.isEmpty ?? true))
                ? null
                : () => _editCrop(_pages![_current]),
          ),
          IconButton(
            key: const Key('page-viewer-export'),
            tooltip: 'Export PDF',
            icon: const Icon(Icons.picture_as_pdf),
            onPressed: (_loading || _error || _exporting ||
                    (_pages?.isEmpty ?? true))
                ? null
                : _exportPdf,
          ),
          IconButton(
            key: const Key('page-viewer-delete'),
            tooltip: 'Delete',
            icon: const Icon(Icons.delete_outline),
            onPressed: (_loading || _error || _exporting) ? null : _confirmAndDelete,
          ),
          PopupMenuButton<String>(
            key: const Key('page-viewer-page-menu'),
            enabled: !(_loading || _error || _exporting || (_pages?.isEmpty ?? true)),
            onSelected: (v) {
              if (v == 'view-text') _viewText();
              if (v == 'rotate') unawaited(_rotatePage());
              if (v == 'merge') unawaited(_mergeAnother());
              if (v == 'split') unawaited(_splitAfter());
              if (v == 'retake') unawaited(_retakePage());
              if (v == 'delete') unawaited(_confirmAndDeletePage());
              if (v == 'export-image') unawaited(_exportPageAsImage());
              if (v == 'export-all-images') unawaited(_exportAllImages());
              if (v == 'print') unawaited(_print());
              if (v == 'protect') unawaited(_protect());
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'view-text',
                key: Key('page-viewer-view-text'),
                child: Text('View text'),
              ),
              PopupMenuItem<String>(
                value: 'rotate',
                key: Key('page-viewer-rotate'),
                child: Text('Rotate'),
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
                value: 'retake',
                key: Key('page-viewer-retake'),
                child: Text('Retake page'),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                key: Key('page-viewer-delete-page'),
                child: Text('Delete page'),
              ),
              PopupMenuItem<String>(
                value: 'export-image',
                key: Key('page-viewer-export-image'),
                child: Text('Export as image'),
              ),
              PopupMenuItem<String>(
                value: 'export-all-images',
                key: Key('page-viewer-export-all-images'),
                child: Text('Export all as images'),
              ),
              PopupMenuItem<String>(
                value: 'print',
                key: Key('page-viewer-print'),
                child: Text('Print'),
              ),
              PopupMenuItem<String>(
                value: 'protect',
                key: Key('page-viewer-protect'),
                child: Text('Protect with password'),
              ),
            ],
          ),
        ],
      ),
      body: _loading
          ? const Center(
              key: Key('page-viewer-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : (_pages == null || _pages!.isEmpty)
                  ? _buildEmpty()
                  : _buildPages(_pages!),
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
          child: PageView.builder(
            controller: _controller,
            itemCount: pages.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (context, i) {
              final pg = pages[i];
              return InteractiveViewer(
                key: Key('page-viewer-page-${pg.position}'),
                child: Image.file(
                  File(pg.displayPath),
                  fit: BoxFit.contain,
                  errorBuilder: (c, e, s) => const Center(
                    child: Icon(Icons.broken_image_outlined, size: 64),
                  ),
                ),
              );
            },
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
