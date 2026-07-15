import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../../l10n/l10n.dart';
import '../../theme/ream_colors.dart';
import '../../theme/widgets/ream_back_header.dart';
import 'feature_flags.dart';
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
  final FeatureFlags features;

  /// Bounds [opener]: a never-returning open (wedged native plugin) must not
  /// leave the spinner up forever. On expiry the [TimeoutException] falls into
  /// the existing catch and routes into the error state.
  final Duration openTimeout;
  const PdfPreviewScreen({
    super.key,
    required this.pdfPath,
    required this.name,
    this.opener = PdfDocument.openFile,
    this.share = const SystemShareChannel(),
    this.features = const FeatureFlags(),
    this.openTimeout = const Duration(seconds: 15),
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
      final doc = await widget
          .opener(widget.pdfPath)
          .timeout(widget.openTimeout);
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
    final r = context.ream;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: widget.name,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: ShareMenuButton(
          buttonKey: const Key('pdf-preview-share'),
          showFax: widget.features.fax,
          showShareLink: widget.features.shareLink,
          onShare: () => unawaited(
            widget.share.share([widget.pdfPath], subject: widget.name),
          ),
        ),
      ),
      body: _loading
          ? const Center(
              key: Key('pdf-preview-loading'),
              child: CircularProgressIndicator(),
            )
          : _error
          ? Center(
              key: const Key('pdf-preview-error'),
              child: Text(
                context.l10n.pdfPreviewOpenError,
                style: TextStyle(fontFamily: 'Figtree', color: r.ink2),
              ),
            )
          : PdfViewPinch(
              key: const Key('pdf-preview-view'),
              controller: _controller!,
            ),
    );
  }
}
