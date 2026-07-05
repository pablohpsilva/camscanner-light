import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import 'share_channel.dart';
import 'widgets/share_menu_button.dart';

/// Opens a PDF file and returns its [PdfDocument]. Injectable so host tests can
/// drive loading/error without the native plugin. Default = pdfx's real opener.
typedef PdfOpener = Future<PdfDocument> Function(String path);

/// Renders [pdfPath] on-device with pinch-zoom ([PdfViewPinch]). The doc is
/// opened in initState via [opener] wrapped in try/catch — pdfx's errorBuilder
/// does NOT catch openFile failures (spike-proven), so error handling lives
/// here, surfacing explicit loading / error / loaded states.
class PdfPreviewScreen extends StatefulWidget {
  final String pdfPath;
  final String name;
  final PdfOpener opener;
  final ShareChannel share;
  const PdfPreviewScreen({
    super.key,
    required this.pdfPath,
    required this.name,
    this.opener = PdfDocument.openFile,
    this.share = const SystemShareChannel(),
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  PdfControllerPinch? _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final doc = await widget.opener(widget.pdfPath);
      if (!mounted) {
        doc.close();
        return;
      }
      setState(() {
        _controller = PdfControllerPinch(document: Future.value(doc));
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

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          ShareMenuButton(
            buttonKey: const Key('pdf-preview-share'),
            onShare: () => unawaited(
              widget.share.share([widget.pdfPath], subject: widget.name),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              key: Key('pdf-preview-loading'),
              child: CircularProgressIndicator())
          : _error
              ? const Center(
                  key: Key('pdf-preview-error'),
                  child: Text("Couldn't open the PDF."))
              : PdfViewPinch(
                  key: const Key('pdf-preview-view'),
                  controller: _controller!,
                ),
    );
  }
}
