import 'package:flutter/material.dart';

import '../document.dart';

/// Basic name + date list of saved documents (B1). No thumbnails — that is B2,
/// and rendering local image files here would risk the Image.file host-test
/// hang. Newest first (the repository orders the list).
class DocumentsListView extends StatelessWidget {
  final List<Document> documents;
  const DocumentsListView({super.key, required this.documents});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      itemCount: documents.length,
      itemBuilder: (context, i) {
        final d = documents[i];
        return ListTile(
          key: Key('document-tile-${d.id}'),
          leading: const Icon(Icons.description_outlined),
          title: Text(d.name),
          subtitle: Text(_formatLocal(d.createdAt.toLocal())),
        );
      },
    );
  }

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
