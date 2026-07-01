import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/library/image_warper.dart';
import 'package:mobile/features/library/perspective_warper.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/drift/app_database.dart' show AppDatabase;
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// In-memory fake repository for host tests. Optionally throws, or blocks on a
/// [gate] so a test can observe the transient `saving` state.
class FakeDocumentRepository implements DocumentRepository {
  final bool throwOnCreate;
  final bool throwOnList;
  final bool throwOnGetPages;
  final bool throwOnDelete;
  final bool throwOnExport;
  final bool throwOnRename;
  final bool throwOnUpdate;
  final bool throwOnAddPage;
  final bool throwOnReorder;
  final bool throwOnDeletePage;
  final bool throwOnReplacePage;
  final bool throwOnExportImage;
  final Completer<void>? gate;
  final Completer<void>? exportGate;
  final Completer<void>? listGate;
  final Completer<void>? addPageGate;
  final List<Document> documents;
  final List<PageImage>? pages; // null => synthesize one non-loadable page
  int createCalls = 0;
  int listCalls = 0;
  CropCorners? lastSavedCorners;
  ImageEnhancer? lastSavedEnhancer;
  int? lastUpdatedPosition;
  CropCorners? lastUpdatedCorners;
  int addPageCalls = 0;
  List<int> lastReorderedPositions = <int>[];
  int? lastDeletedPagePosition;
  int? lastReplacedPagePosition;
  final List<int> deletedIds = <int>[];
  final List<int> exportedIds = <int>[];
  final List<String> renamedTo = <String>[];
  int? lastExportedImagePosition;

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.throwOnList = false,
    this.throwOnGetPages = false,
    this.throwOnDelete = false,
    this.throwOnExport = false,
    this.throwOnRename = false,
    this.throwOnUpdate = false,
    this.throwOnAddPage = false,
    this.throwOnReorder = false,
    this.throwOnDeletePage = false,
    this.throwOnReplacePage = false,
    this.throwOnExportImage = false,
    this.gate,
    this.exportGate,
    this.listGate,
    this.addPageGate,
    List<Document>? documents,
    this.pages,
  }) : documents = documents ?? <Document>[];

  late final List<PageImage>? _working =
      pages == null ? null : List<PageImage>.from(pages!);

  @override
  Future<Document> createFromCapture(CapturedImage capture,
      {CropCorners? corners, ImageEnhancer? enhancer}) async {
    createCalls++;
    lastSavedCorners = corners;
    lastSavedEnhancer = enhancer;
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
  Future<List<PageImage>> getDocumentPages(int documentId) async {
    if (throwOnGetPages) throw StateError('fake: getDocumentPages failed');
    final w = _working;
    return w == null
        ? [PageImage(position: 1, imagePath: '/nonexistent/page-$documentId-1.jpg')]
        : List<PageImage>.from(w);
  }

  @override
  Future<void> deleteDocument(int documentId) async {
    if (throwOnDelete) throw StateError('fake: delete failed');
    deletedIds.add(documentId);
    documents.removeWhere((d) => d.id == documentId);
  }

  @override
  Future<File> exportPdf(int documentId) async {
    if (throwOnExport) {
      throw const DocumentExportException('fake: export failed');
    }
    if (exportGate != null) await exportGate!.future;
    exportedIds.add(documentId);
    // Return a path without real I/O — callers (e.g. _exportPdf) discard the
    // File; widget tests need the future to complete synchronously so that
    // pumpAndSettle can drive the success SnackBar before settling.
    return File('${Directory.systemTemp.path}/fake-export-$documentId.pdf');
  }

  @override
  Future<File> exportPageAsImage(int documentId, int position) async {
    if (throwOnExportImage) {
      throw const DocumentExportException('fake: exportImage failed');
    }
    lastExportedImagePosition = position;
    return File(
        '${Directory.systemTemp.path}/fake-export-$documentId-$position.jpg');
  }

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    listCalls++;
    if (listGate != null) await listGate!.future;
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

  @override
  Future<Document> rename(int documentId, String newName) async {
    if (throwOnRename) {
      throw const DocumentRenameException('fake: rename failed');
    }
    final trimmed = newName.trim();
    renamedTo.add(trimmed);
    final i = documents.indexWhere((d) => d.id == documentId);
    // Build the updated doc. modifiedAt is left as-is: host tests never assert
    // it (the list UI shows createdAt); the real Drift repo owns the clock+bump.
    final base = i >= 0
        ? documents[i]
        : Document(
            id: documentId,
            name: trimmed,
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42));
    final updated = Document(
      id: base.id,
      name: trimmed,
      createdAt: base.createdAt,
      modifiedAt: base.modifiedAt,
    );
    if (i >= 0) documents[i] = updated; // so listDocumentSummaries reflects it
    return updated;
  }

  @override
  Future<void> updatePageCorners(
      int documentId, int position, CropCorners corners) async {
    if (throwOnUpdate) {
      throw DocumentSaveException('fake: update failed');
    }
    lastUpdatedPosition = position;
    lastUpdatedCorners = corners;
  }

  @override
  Future<int> addPageToDocument(
    int documentId,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    addPageCalls++;
    if (addPageGate != null) await addPageGate!.future;
    if (throwOnAddPage) {
      throw const DocumentSaveException('fake: addPage failed');
    }
    return addPageCalls + 1; // 2 on first call (position 1 already taken)
  }

  @override
  Future<void> reorderPages(int documentId, List<int> orderedPositions) async {
    if (throwOnReorder) {
      throw const DocumentSaveException('fake: reorder failed');
    }
    lastReorderedPositions = List<int>.unmodifiable(orderedPositions);
  }

  @override
  Future<int> deletePage(int documentId, int position) async {
    if (throwOnDeletePage) {
      throw const DocumentSaveException('fake: deletePage failed');
    }
    final w = _working;
    if (w == null) {
      // Synthesized single page: deleting it removes the document.
      if (position != 1) {
        throw const DocumentSaveException('fake: no such page');
      }
      lastDeletedPagePosition = position;
      return 0;
    }
    final idx = w.indexWhere((p) => p.position == position);
    if (idx < 0) {
      throw const DocumentSaveException('fake: no such page');
    }
    w.removeAt(idx);
    // Renumber survivors contiguously 1..N.
    for (var i = 0; i < w.length; i++) {
      final p = w[i];
      w[i] = PageImage(
        position: i + 1,
        imagePath: p.imagePath,
        corners: p.corners,
        flatImagePath: p.flatImagePath,
      );
    }
    lastDeletedPagePosition = position;
    return w.length;
  }

  @override
  Future<void> replacePage(
    int documentId,
    int position,
    CapturedImage capture, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    if (throwOnReplacePage) {
      throw const DocumentSaveException('fake: replacePage failed');
    }
    final w = _working;
    if (w != null && w.indexWhere((p) => p.position == position) < 0) {
      throw const DocumentSaveException('fake: no such page');
    }
    lastReplacedPagePosition = position;
  }
}

/// Fake [ImageWarper] for host tests. Configurable to return fixed bytes,
/// or throw [WarpException].
///
/// Default [returnValue] is a non-null stub so tests that pass non-full-frame
/// corners get a flat derivative without providing explicit bytes.
class FakeImageWarper implements ImageWarper {
  final bool throws;
  final Uint8List returnValue;
  int calls = 0;

  FakeImageWarper({this.throws = false, Uint8List? returnValue})
      : returnValue =
            returnValue ?? Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async {
    calls++;
    if (throws) throw WarpException('fake: warp failed');
    return returnValue;
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
        pdfBuilder: const PdfBuilder(),
        warper: const PerspectiveWarper(),
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
        pdfBuilder: const PdfBuilder(),
        warper: const PerspectiveWarper(),
      ),
    );
