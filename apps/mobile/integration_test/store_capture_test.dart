// Store-listing screenshot capture harness.
//
// Drives the app into six clean, seeded states and holds each on-screen while
// an external orchestrator (store/capture.sh) grabs an OS-level screenshot via
// simctl/adb. OS capture (not binding.takeScreenshot) is used deliberately so
// native platform views — the pdfx PDF preview especially — render correctly.
//
// Sync protocol: at each state the test prints `@@SHOT:<name>@@`, then holds the
// frame for ~3s by pumping in a loop. The orchestrator watches stdout for the
// marker and captures during the hold.
//
// Run (per device), via store/capture.sh:
//   flutter test integration_test/store_capture_test.dart -d <device-id>
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/l10n/lb_fallback_delegates.dart';
import 'package:mobile/main.dart' as app;

import '../test/support/fake_library.dart';
import '../test/support/fake_scan.dart';
import '../test/support/store_fixtures.g.dart';

/// One seeded document: name, fixture image key, and OCR text for FTS search.
class _Doc {
  final String name;
  final String fixture;
  final String ocr;
  const _Doc(this.name, this.fixture, this.ocr);
}

const _docs = <_Doc>[
  _Doc(
    'Acme Corporation Invoice',
    'invoice',
    'ACME CORPORATION INVOICE INV-2048 brand identity design website UI '
        'mockups printed brochure layout photography licensing total 4000',
  ),
  _Doc(
    'Q2 Final Report',
    'report',
    'ACME CORPORATION Q2 Final Report quarterly revenue grew 24 percent '
        'highlights outlook finance retention',
  ),
  _Doc(
    'Oak Cafe Receipt',
    'receipt',
    'Oak Cafe receipt order flat white almond croissant sparkling water '
        'total 16.50',
  ),
];

/// Seeds a real on-device SQLite file + file store: three documents, each with
/// its fixture JPEG written to disk and OCR text indexed by the FTS5 triggers.
/// Returns (dbFile, baseDir) for the app / repository to open the SAME storage.
Future<(File, Directory)> _seed() async {
  final baseDir = await Directory.systemTemp.createTemp('store_shots');
  final dbFile = File('${baseDir.path}/camscanner.sqlite');
  final db = AppDatabase(NativeDatabase(dbFile));
  // Oldest first so "Created" desc sort shows Invoice at the top.
  var when = DateTime.now().subtract(const Duration(minutes: 30));
  for (final d in _docs) {
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: d.name,
            createdAt: when,
            modifiedAt: when,
          ),
        );
    final rel = 'documents/$id/page_1.jpg';
    await File('${baseDir.path}/$rel').create(recursive: true);
    await File(
      '${baseDir.path}/$rel',
    ).writeAsBytes(storeFixtureBytes(d.fixture));
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            ocrText: Value(d.ocr),
          ),
        );
    when = when.add(const Duration(minutes: 10));
  }
  await db.close();
  return (dbFile, baseDir);
}

/// Writes the invoice fixture to a standalone temp file for the review screen.
Future<CapturedImage> _invoiceCapture() async {
  final dir = await Directory.systemTemp.createTemp('store_cap');
  final f = File('${dir.path}/invoice.jpg')
    ..writeAsBytesSync(storeFixtureBytes('invoice'));
  return CapturedImage(f.path);
}

/// Prints the capture marker and holds the current frame ~3s so the external
/// orchestrator can grab an OS screenshot mid-hold.
Future<void> _hold(WidgetTester tester, String name) async {
  await tester.pumpAndSettle(const Duration(milliseconds: 500));
  // ignore: avoid_print
  print('@@SHOT:$name@@');
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('library — document list', (tester) async {
    final (dbFile, baseDir) = await _seed();
    app.runCamScannerApp(
      scanDependencies: grantedScanDependencies(),
      libraryDependencies: persistentLibraryDependencies(
        dbFile: dbFile,
        baseDir: baseDir,
      ),
    );
    await _hold(tester, 'library');
  });

  testWidgets('search — full-text results', (tester) async {
    final (dbFile, baseDir) = await _seed();
    app.runCamScannerApp(
      scanDependencies: grantedScanDependencies(),
      libraryDependencies: persistentLibraryDependencies(
        dbFile: dbFile,
        baseDir: baseDir,
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    // The Ream search field is always visible in the header (no icon to open).
    await tester.enterText(
      find.byKey(const Key('documents-search-field')),
      'acme',
    );
    await tester.pump(const Duration(milliseconds: 300));
    // Drop focus so the Android soft keyboard + floating edit toolbar dismiss,
    // leaving the query text and results cleanly visible (iOS is already clean).
    FocusManager.instance.primaryFocus?.unfocus();
    await _hold(tester, 'search');
  });

  testWidgets('scan — capture review with edge detection', (tester) async {
    final capture = await _invoiceCapture();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaptureReviewScreen(
          image: capture,
          onRetake: () {},
          onAccept: (CropCorners _, ImageEnhancer _) {},
        ),
      ),
    );
    await _hold(tester, 'scan');
  });

  testWidgets('filters — grayscale filter selected', (tester) async {
    final capture = await _invoiceCapture();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: CaptureReviewScreen(
          image: capture,
          onRetake: () {},
          onAccept: (CropCorners _, ImageEnhancer _) {},
        ),
      ),
    );
    await tester.pumpAndSettle(const Duration(milliseconds: 600));
    final grayscale = find.byKey(const Key('filter-tile-grayscale'));
    if (grayscale.evaluate().isNotEmpty) {
      await tester.tap(grayscale);
    }
    await _hold(tester, 'filters');
  });

  testWidgets('pdf — export preview', (tester) async {
    final (dbFile, baseDir) = await _seed();
    final repo =
        await persistentLibraryDependencies(
              dbFile: dbFile,
              baseDir: baseDir,
            ).createRepository()
            as DriftDocumentRepository;
    // Newest-first list puts the receipt id highest; export the invoice (id 1).
    final pdf = await repo.exportPdf(1);
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfPreviewScreen(
          pdfPath: pdf.path,
          name: 'Acme Corporation Invoice',
        ),
      ),
    );
    await _hold(tester, 'pdf');
  });

  testWidgets('viewer — full page, on-device OCR', (tester) async {
    final (dbFile, baseDir) = await _seed();
    final repo =
        await persistentLibraryDependencies(
              dbFile: dbFile,
              baseDir: baseDir,
            ).createRepository()
            as DriftDocumentRepository;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: PageViewerScreen(
          documentId: 1,
          name: 'Acme Corporation Invoice',
          repository: repo,
        ),
      ),
    );
    await _hold(tester, 'privacy');
  });
}
