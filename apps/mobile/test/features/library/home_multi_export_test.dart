import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';

/// Recording archiver: captures the zip call, returns a stub file (no I/O).
class FakeFileArchiver implements FileArchiver {
  int calls = 0;
  List<String>? lastEntryNames;
  String? lastArchiveName;
  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    calls++;
    lastArchiveName = archiveName;
    lastEntryNames = entryNames;
    return File('${Directory.systemTemp.path}/$archiveName');
  }
}

Document _doc(int id, String name) => Document(
      id: id,
      name: name,
      // doc1 newer than doc2 → default (created,desc) sort = display order [1,2]
      createdAt: DateTime.utc(2026, 7, 6, 12 - id),
      modifiedAt: DateTime.utc(2026, 7, 6, 12 - id),
    );

void main() {
  late FakeDocumentRepository repo;
  late FakeShareChannel share;
  late FakeFileArchiver archiver;

  LibraryDependencies deps() => LibraryDependencies(
        createRepository: () async => repo,
        share: share,
        archiver: archiver,
      );

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: const ScanDependencies(),
        libraryDependencies: deps(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    repo = FakeDocumentRepository(
      documents: [_doc(1, 'Alpha'), _doc(2, 'Beta')],
    );
    share = FakeShareChannel();
    archiver = FakeFileArchiver();
  });

  testWidgets('long-press enters selection; title shows count; close clears',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-close')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('Documents'), findsOneWidget); // back to normal app bar
  });

  testWidgets('one selected → Export shares a single PDF, no zip',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();

    expect(repo.exportedIds, [1]);
    expect(archiver.calls, 0);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastMimeType, isNull);
    // selection cleared after success
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('two selected → Export zips separate PDFs and shares the zip',
      (tester) async {
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();

    expect(repo.separateExportCalls.single, [1, 2]); // displayed (sorted) order
    expect(archiver.calls, 1);
    expect(archiver.lastArchiveName, 'documents.zip');
    expect(archiver.lastEntryNames, ['Alpha.pdf', 'Beta.pdf']);
    expect(share.lastFilePaths!.single, endsWith('.zip'));
    expect(share.lastMimeType, 'application/zip');
    expect(find.text('2 selected'), findsNothing);
  });

  testWidgets('a failing export shows the "Couldn\'t share" snackbar',
      (tester) async {
    repo = FakeDocumentRepository(
      documents: [_doc(1, 'Alpha'), _doc(2, 'Beta')],
      throwOnExport: true,
    );
    await pumpHome(tester);
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't share"), findsOneWidget);
    expect(find.text('2 selected'), findsOneWidget); // selection persists on failure
  });
}
