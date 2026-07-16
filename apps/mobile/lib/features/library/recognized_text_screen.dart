import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'share_channel.dart';

import '../../l10n/l10n.dart';
import '../../theme/ream_colors.dart';
import '../../core/ui/error_snack.dart';
import '../../theme/widgets/confidence_chip.dart';
import '../../theme/widgets/ream_action_button.dart';
import '../../theme/widgets/ream_back_header.dart';
import 'document_repository.dart';
import 'page_image.dart';

/// Shows a single page's cached OCR text: selectable, copyable, exportable as a
/// temporary `.txt` via the share sheet. Loads the text authoritatively from
/// the repository on init (with [initialText] as an instant-render seed), so it
/// stays correct even if the caller's cached text is stale. When the page has
/// no text yet, offers an on-demand "Recognize text" action (`runOcr`).
class RecognizedTextScreen extends StatefulWidget {
  final int documentId;
  final int position;
  final String name;
  final String? initialText;
  final DocumentRepository repository;
  final ShareChannel share;

  const RecognizedTextScreen({
    super.key,
    required this.documentId,
    required this.position,
    required this.name,
    required this.repository,
    this.initialText,
    this.share = const SystemShareChannel(),
  });

  @override
  State<RecognizedTextScreen> createState() => _RecognizedTextScreenState();
}

class _RecognizedTextScreenState extends State<RecognizedTextScreen> {
  String? _text;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _text = widget.initialText;
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final pages = await widget.repository.getDocumentPages(widget.documentId);
      if (!mounted) return;
      PageImage? page;
      for (final p in pages) {
        if (p.position == widget.position) {
          page = p;
          break;
        }
      }
      setState(() => _text = page?.ocrText);
    } catch (_) {
      // Keep whatever seed we had; surface nothing catastrophic.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recognize() async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    try {
      await widget.repository.runOcr(widget.documentId, widget.position);
      await _load();
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnack(l10n.ocrErrorRecognize);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final t = _text;
    if (t == null || t.isEmpty) return;
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.commonCopied)));
  }

  Future<void> _share() async {
    final l10n = context.l10n;
    try {
      final file = await widget.repository.exportRecognizedText(
        widget.documentId,
        widget.position,
      );
      await widget.share.share([file.path], subject: widget.name);
    } catch (_) {
      if (!mounted) return;
      context.showErrorSnack(l10n.ocrErrorExport);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final l10n = context.l10n;
    final text = _text;
    final hasText = text != null && text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: l10n.ocrTitle,
        onBack: () => Navigator.of(context).maybePop(),
        backKey: const Key('recognized-text-back'),
      ),
      body: _busy && text == null
          ? const Center(
              key: Key('recognized-text-loading'),
              child: CircularProgressIndicator(),
            )
          : hasText
          ? Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: ConfidenceChip(
                      level: ConfidenceLevel.high,
                      label: l10n.ocrTextLayerReady,
                    ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: SelectableText(
                      text,
                      key: const Key('recognized-text-body'),
                      style: TextStyle(
                        fontFamily: 'Figtree',
                        fontSize: 13,
                        height: 1.7,
                        color: r.ink2,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: ReamActionButton(
                          key: const Key('recognized-text-copy'),
                          label: l10n.ocrCopyText,
                          onPressed: (_busy || !hasText) ? null : _copy,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: ReamActionButton(
                          key: const Key('recognized-text-share'),
                          label: l10n.ocrShareTxt,
                          primary: true,
                          fillColor: r.ink,
                          onPressed: (_busy || !hasText)
                              ? null
                              : () => unawaited(_share()),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Center(
              key: const Key('recognized-text-empty'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.ocrEmpty,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 14,
                      color: r.ink2,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    key: const Key('recognized-text-run'),
                    onPressed: _busy ? null : _recognize,
                    child: Text(l10n.ocrRecognizeButton),
                  ),
                ],
              ),
            ),
    );
  }
}
