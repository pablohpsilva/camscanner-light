import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';

/// Usage: the exported PDF has 3 pages
///
/// Reads the mounted preview screen's real on-disk PDF path and counts its page
/// objects directly from the file bytes (`/Type /Page`, excluding the `/Pages`
/// tree root) — the same reliable technique the unit tests use.
///
/// NOTE: we deliberately do NOT open the file with pdfx here. The preview screen
/// already holds an open native pdfx handle on this exact file; opening a second
/// native handle on the same file on-device deadlocks/crashes the renderer
/// (observed: the scenario hung and the app relaunched mid-test). A pure byte
/// read has no such conflict and still proves the written PDF's page count
/// end-to-end.
Future<void> theExportedPdfHas3Pages(WidgetTester tester) async {
  final screen =
      tester.widget<PdfPreviewScreen>(find.byType(PdfPreviewScreen));
  final bytes = await File(screen.pdfPath).readAsBytes();
  final s = latin1.decode(bytes, allowInvalid: true);
  final pageCount = RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length;
  expect(pageCount, 3);
}
