import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> tapPrint(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-print')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Print sends the exported PDF to the printer', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final printer = FakeDocumentPrinter();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 3, name: 'Report', repository: repo, printer: printer),
    ));
    await tester.pumpAndSettle();

    await tapPrint(tester);

    expect(printer.lastName, 'Report');
    expect(printer.lastFile, isNotNull);
    expect(find.text('Sent to printer'), findsOneWidget);
  });

  testWidgets('a failing export shows a print error', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExport: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final printer = FakeDocumentPrinter();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 3, name: 'Report', repository: repo, printer: printer),
    ));
    await tester.pumpAndSettle();

    await tapPrint(tester);

    expect(printer.lastFile, isNull);
    expect(find.text("Couldn't print"), findsOneWidget);
  });
}
