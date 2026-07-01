import 'package:flutter/material.dart';

import 'document_repository.dart';
import 'document_summary.dart';

/// Shows a dialog listing every document EXCEPT [currentDocumentId] and resolves
/// to the chosen document's id (or null if cancelled / none available).
Future<int?> showMergePicker(
    BuildContext context, DocumentRepository repository, int currentDocumentId) {
  return showDialog<int>(
    context: context,
    builder: (_) => MergePickerDialog(
        repository: repository, currentDocumentId: currentDocumentId),
  );
}

class MergePickerDialog extends StatefulWidget {
  final DocumentRepository repository;
  final int currentDocumentId;
  const MergePickerDialog({
    super.key,
    required this.repository,
    required this.currentDocumentId,
  });

  @override
  State<MergePickerDialog> createState() => _MergePickerDialogState();
}

class _MergePickerDialogState extends State<MergePickerDialog> {
  List<DocumentSummary>? _others;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await widget.repository.listDocumentSummaries();
      if (!mounted) return;
      setState(() => _others = all
          .where((s) => s.document.id != widget.currentDocumentId)
          .toList());
    } catch (_) {
      if (mounted) setState(() => _others = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final others = _others;
    return AlertDialog(
      key: const Key('merge-picker-dialog'),
      title: const Text('Merge another document'),
      content: SizedBox(
        width: double.maxFinite,
        child: others == null
            ? const SizedBox(
                height: 64,
                child: Center(child: CircularProgressIndicator()))
            : others.isEmpty
                ? const Padding(
                    key: Key('merge-picker-empty'),
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('No other documents to merge.'),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: [
                      for (final s in others)
                        ListTile(
                          key: Key('merge-picker-item-${s.document.id}'),
                          title: Text(s.document.name),
                          subtitle: Text(s.pageCount == 1
                              ? '1 page'
                              : '${s.pageCount} pages'),
                          onTap: () =>
                              Navigator.of(context).pop(s.document.id),
                        ),
                    ],
                  ),
      ),
      actions: [
        TextButton(
          key: const Key('merge-picker-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
