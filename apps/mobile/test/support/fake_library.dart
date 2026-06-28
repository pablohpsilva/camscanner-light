import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/drift/app_database.dart' show AppDatabase;
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// In-memory fake repository for host tests. Optionally throws, or blocks on a
/// [gate] so a test can observe the transient `saving` state.
class FakeDocumentRepository implements DocumentRepository {
  final bool throwOnCreate;
  final bool throwOnList;
  final Completer<void>? gate;
  final List<Document> documents;
  int createCalls = 0;

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.throwOnList = false,
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
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    if (throwOnList) {
      throw StateError('fake: list failed');
    }
    // Synthesize: every fake document has one page and a deliberately
    // NON-LOADABLE thumbnail path (host tests must not load a real Image.file).
    return List<DocumentSummary>.unmodifiable(documents.map((d) =>
        DocumentSummary(
            document: d,
            pageCount: 1,
            thumbnailPath: '/nonexistent/thumb-${d.id}.jpg')));
  }
}

/// LibraryDependencies whose factory returns the given fake repository.
LibraryDependencies fakeLibraryDependencies(FakeDocumentRepository repo) =>
    LibraryDependencies(createRepository: () async => repo);

/// Real DriftDocumentRepository on an in-memory DB + temp file store. Exercises
/// the real save/scrub/list code paths deterministically with no persistent
/// side effects — used by the BDD success scenario on-device.
LibraryDependencies tempLibraryDependencies() => LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase.memory()),
        scrubber: const JpegExifScrubber(),
        fileStore:
            DocumentFileStore(await Directory.systemTemp.createTemp('b1bdd')),
        clock: DateTime.now,
      ),
    );

/// Library deps whose repository always fails — for the save-failure scenario.
LibraryDependencies failingLibraryDependencies() =>
    fakeLibraryDependencies(FakeDocumentRepository(throwOnCreate: true));

/// A persistent (file-backed) LibraryDependencies that reuses the SAME db file
/// and documents baseDir on every createRepository() call — so data written
/// before one app pump is still there when a later pump reads it. This is the
/// Tier-2 restart proof. (Contrast tempLibraryDependencies(), which builds a
/// fresh NativeDatabase.memory() AND a fresh temp dir per call, and therefore
/// cannot persist across a re-pump.)
LibraryDependencies persistentLibraryDependencies({
  required File dbFile,
  required Directory baseDir,
}) =>
    LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase(dbFile)),
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(baseDir),
        clock: DateTime.now,
      ),
    );
