import 'dart:async';

import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// In-memory fake repository for host tests. Optionally throws, or blocks on a
/// [gate] so a test can observe the transient `saving` state.
class FakeDocumentRepository implements DocumentRepository {
  final bool throwOnCreate;
  final Completer<void>? gate;
  final List<Document> documents;
  int createCalls = 0;

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.gate,
    List<Document>? documents,
  }) : documents = documents ?? <Document>[];

  @override
  Future<Document> createFromCapture(CapturedImage capture) async {
    createCalls++;
    if (gate != null) await gate!.future;
    if (throwOnCreate) {
      throw const DocumentSaveException('fake: save failed');
    }
    final doc = Document(
      id: documents.length + 1,
      name: 'Scan 2026-06-27 20.26.42',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    );
    documents.insert(0, doc);
    return doc;
  }

  @override
  Future<List<Document>> listDocuments() async =>
      List<Document>.unmodifiable(documents);
}

/// LibraryDependencies whose factory returns the given fake repository.
LibraryDependencies fakeLibraryDependencies(FakeDocumentRepository repo) =>
    LibraryDependencies(createRepository: () async => repo);
