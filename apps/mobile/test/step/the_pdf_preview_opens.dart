import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the PDF preview opens
///
/// The PdfViewPinch (keyed pdf-preview-view) only mounts if exportPdf wrote a
/// valid PDF and pdfx opened+rendered it on-device — a full round-trip proof.
Future<void> thePdfPreviewOpens(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('pdf-preview-view')), findsOneWidget);
}
