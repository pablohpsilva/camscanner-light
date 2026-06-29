import 'dart:io';

import 'package:flutter/material.dart';

import 'document_repository.dart';
import 'page_image.dart';
import 'pdf_preview_screen.dart';
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
  const PageViewerScreen({
    super.key,
    required this.documentId,
    required this.name,
    required this.repository,
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
    setState(() => _exporting = true);
    try {
      final file = await widget.repository.exportPdf(widget.documentId);
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              PdfPreviewScreen(pdfPath: file.path, name: _name),
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
    return Stack(
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
                fit: BoxFit.contain,
                errorBuilder: (c, e, s) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 64),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 16,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              '${_current + 1} / ${pages.length}',
              key: const Key('page-viewer-indicator'),
            ),
          ),
        ),
      ],
    );
  }
}
