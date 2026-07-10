import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

Future<void> _pumpViewer(
  WidgetTester tester,
  FakeDocumentRepository repo,
  FakeShareChannel share,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PageViewerScreen(
        repository: repo,
        documentId: 4,
        name: 'Doc',
        share: share,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('image share: choosing Medium passes quality + shares', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    final share = FakeShareChannel();
    await _pumpViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, ExportQuality.medium);
    expect(share.calls, 1);
  });

  testWidgets('image share: cancelling the dialog is a no-op', (tester) async {
    final repo = FakeDocumentRepository();
    final share = FakeShareChannel();
    await _pumpViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(repo.lastImageExportQuality, isNull);
    expect(share.calls, 0);
  });

  testWidgets('PDF export: choosing Low passes quality (pump, not settle)', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await _pumpViewer(tester, repo, FakeShareChannel());
    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pumpAndSettle(); // dialog animates in
    await tester.tap(find.byKey(const Key('export-quality-low')));
    await tester.pump(); // NOT settle — the pushed pdfx preview hangs settle
    await tester.pump();
    expect(repo.lastExportQuality, ExportQuality.low);
  });
}
