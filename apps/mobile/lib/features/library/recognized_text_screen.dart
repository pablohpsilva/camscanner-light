import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'share_channel.dart';

import 'document_repository.dart';
import 'page_image.dart';
import 'widgets/share_menu_button.dart';

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
    final text = _text;
    final hasText = text != null && text.trim().isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Text'),
        actions: [
          IconButton(
            key: const Key('recognized-text-copy'),
            tooltip: 'Copy',
            icon: const Icon(Icons.copy),
            onPressed: (_busy || !hasText) ? null : _copy,
          ),
          ShareMenuButton(
            buttonKey: const Key('recognized-text-share'),
            onShare: () => unawaited(_share()),
            showFax: false,
            enabled: !(_busy || !hasText),
          ),
        ],
      ),
      body: _busy && text == null
          ? const Center(
              key: Key('recognized-text-loading'),
              child: CircularProgressIndicator(),
            )
          : hasText
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                text,
                key: const Key('recognized-text-body'),
              ),
            )
          : Center(
              key: const Key('recognized-text-empty'),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No text recognized on this page yet.'),
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
