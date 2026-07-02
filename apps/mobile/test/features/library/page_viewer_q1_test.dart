import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

Future<void> _pumpViewer(WidgetTester tester, FakeDocumentRepository repo) async {
  await tester.pumpWidget(MaterialApp(
    home: PageViewerScreen(
      repository: repo,
      documentId: 4,
      name: 'Doc',
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('image export: choosing Medium passes quality + confirms',
      (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, ExportQuality.medium);
    expect(find.text('Page saved as image'), findsOneWidget);
  });

  testWidgets('image export: cancelling the dialog is a no-op', (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, isNull);
    expect(find.text('Page saved as image'), findsNothing);
  });

  testWidgets('PDF export: choosing Low passes quality (pump, not settle)',
      (tester) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-low')));
    await tester.pump(); // NOT settle — the pushed pdfx preview hangs settle
    await tester.pump();
    expect(repo.lastExportQuality, ExportQuality.low);
  });
}
