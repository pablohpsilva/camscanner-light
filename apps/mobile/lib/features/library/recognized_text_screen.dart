import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'share_channel.dart';

import '../../theme/ream_colors.dart';
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
    setState(() => _busy = true);
    try {
      await widget.repository.runOcr(widget.documentId, widget.position);
      await _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't recognize text")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copy() async {
    final t = _text;
    if (t == null || t.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: t));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied')));
  }

  Future<void> _share() async {
    try {
      final file = await widget.repository.exportRecognizedText(
        widget.documentId,
        widget.position,
      );
      await widget.share.share([file.path], subject: widget.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't export text")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final text = _text;
    final hasText = text != null && text.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: 'Recognized text',
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
                      label: 'Text layer ready · powers search',
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
                          label: 'Copy text',
                          onPressed: (_busy || !hasText) ? null : _copy,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: ReamActionButton(
                          key: const Key('recognized-text-share'),
                          label: 'Share .txt',
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
                    'No text recognized on this page yet.',
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
                    child: const Text('Recognize text'),
                  ),
                ],
              ),
            ),
    );
  }
}
