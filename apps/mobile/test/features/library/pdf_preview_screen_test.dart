import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:pdfx/pdfx.dart';

void main() {
  // A loaded/render path needs the native plugin + a real PdfDocument that
  // cannot be faked, so it is covered on-device. Host tests drive the two
  // states reachable with an injected opener: loading and error.

  testWidgets('shows the loading state while the document opens', (
    tester,
  ) async {
    // An opener that never completes -> stays in loading.
    Future<PdfDocument> neverOpens(String _) => Completer<PdfDocument>().future;
    await tester.pumpWidget(
      MaterialApp(
        home: PdfPreviewScreen(
          pdfPath: '/x/export.pdf',
          name: 'Scan',
          opener: neverOpens,
        ),
      ),
    );
    await tester.pump(); // one frame; do NOT settle (opener never completes)
    expect(find.byKey(const Key('pdf-preview-loading')), findsOneWidget);
  });

  testWidgets('shows the error state when the document fails to open', (
    tester,
  ) async {
    Future<PdfDocument> throws(String _) async =>
        throw StateError('cannot open');
    await tester.pumpWidget(
      MaterialApp(
        home: PdfPreviewScreen(
          pdfPath: '/x/export.pdf',
          name: 'Scan',
          opener: throws,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pdf-preview-error')), findsOneWidget);
    expect(find.byKey(const Key('pdf-preview-loading')), findsNothing);
  });
}
