import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:pdfx/pdfx.dart';

/// Usage: the exported PDF has 3 pages
///
/// Reads the mounted preview screen's real on-disk PDF path and opens it with
/// pdfx (the same opener the screen uses) to assert the file itself has three
/// pages — a genuine on-device page-count check against the written PDF.
Future<void> theExportedPdfHas3Pages(WidgetTester tester) async {
  final screen =
      tester.widget<PdfPreviewScreen>(find.byType(PdfPreviewScreen));
  final doc = await PdfDocument.openFile(screen.pdfPath);
  expect(doc.pagesCount, 3);
  await doc.close();
}
