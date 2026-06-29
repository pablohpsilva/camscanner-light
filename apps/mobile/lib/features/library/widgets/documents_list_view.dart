import 'package:flutter/material.dart';

import '../document_summary.dart';
import 'document_thumbnail.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Rendered in
/// the order it is given — the caller (HomeScreen) applies the user's chosen
/// sort (D3). Each row has an optional overflow menu (Rename) when [onRename]
/// is provided.
class DocumentsListView extends StatelessWidget {
  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];
        final d = s.document;
        return ListTile(
          key: Key('document-tile-${d.id}'),
          leading: DocumentThumbnail(
              key: Key('document-thumb-${d.id}'), path: s.thumbnailPath),
          title: Text(d.name),
          subtitle: Text(
              '${_formatLocal(d.createdAt.toLocal())} · ${_pages(s.pageCount)}'),
          trailing: onRename == null
              ? null
              : PopupMenuButton<String>(
                  key: Key('document-menu-${d.id}'),
                  tooltip: 'Document options',
                  onSelected: (_) => onRename!(s),
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      key: Key('document-rename-${d.id}'),
                      value: 'rename',
                      child: const Text('Rename'),
                    ),
                  ],
                ),
          onTap: onOpen == null ? null : () => onOpen!(s),
        );
      },
    );
  }

  String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
