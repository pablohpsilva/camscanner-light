import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/selection_exporter.dart';
import 'package:mobile/features/library/share_channel.dart';

import '../../support/fake_library.dart';

class _RecordingShare implements ShareChannel {
  final calls = <({List<String> paths, String? subject, String? mimeType})>[];
  @override
  Future<void> share(
    List<String> filePaths, {
    String? subject,
    String? mimeType,
  }) async {
    calls.add((paths: filePaths, subject: subject, mimeType: mimeType));
  }
}

class _RecordingArchiver implements FileArchiver {
  List<String>? lastEntryNames;
  String? lastArchiveName;
  @override
  Future<File> zip(
    List<File> files, {
    required String archiveName,
    required List<String> entryNames,
  }) async {
    lastArchiveName = archiveName;
    lastEntryNames = entryNames;
    return File('/tmp/$archiveName');
  }
}

DocumentSummary _summary(int id, String name) => DocumentSummary(
  document: Document(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 1, 1),
    modifiedAt: DateTime.utc(2026, 1, 1),
  ),
  pageCount: 1,
  thumbnailPath: null,
);

void main() {
  test(
    'a single selected document shares ONE PDF with its name as subject',
    () async {
      final repo = FakeDocumentRepository();
      final share = _RecordingShare();
      final archiver = _RecordingArchiver();
      final exporter = SelectionExporter(
        repository: repo,
        share: share,
        archiver: archiver,
      );

      await exporter.exportAndShare([_summary(1, 'Invoice')]);

      expect(share.calls, hasLength(1));
      expect(share.calls.single.subject, 'Invoice');
      expect(share.calls.single.mimeType, isNull); // a bare PDF, not a zip
      expect(archiver.lastEntryNames, isNull); // no zip for a single doc
    },
  );

  test(
    'multiple selected documents zip per-doc PDFs; entry names are basenames',
    () async {
      final repo = FakeDocumentRepository();
      final share = _RecordingShare();
      final archiver = _RecordingArchiver();
      final exporter = SelectionExporter(
        repository: repo,
        share: share,
        archiver: archiver,
      );

      await exporter.exportAndShare([_summary(1, 'A'), _summary(2, 'B')]);

      // Zipped, entry names are the basenames of the per-doc PDF temp files.
      expect(archiver.lastArchiveName, 'documents.zip');
      expect(archiver.lastEntryNames, isNotNull);
      for (final name in archiver.lastEntryNames!) {
        expect(
          name,
          isNot(contains('/')),
          reason: 'entry name must be a basename',
        );
        expect(name, endsWith('.pdf'));
      }
      expect(share.calls.single.mimeType, 'application/zip');
    },
  );
}
