import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:pdfx/pdfx.dart';

import '../../support/localized_app.dart';

void main() {
  testWidgets('PDF viewer uses Ream chrome (header title + paper bg)', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: PdfPreviewScreen(
          pdfPath: '/nonexistent.pdf',
          name: 'Lease Agreement',
          opener: (_) async => throw Exception('no native in host'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lease Agreement'), findsOneWidget);
    expect(find.byKey(const Key('ream-back')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ReamColors.light.paper);
    // error branch still reachable + keyed
    expect(find.byKey(const Key('pdf-preview-error')), findsOneWidget);
  });

  testWidgets('PDF viewer uses dark paper under the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.dark(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PdfPreviewScreen(
          pdfPath: '/nonexistent.pdf',
          name: 'Lease Agreement',
          opener: (_) async => throw Exception('no native in host'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ReamColors.dark.paper);
  });

  // A loaded/render path needs the native plugin + a real PdfDocument that
  // cannot be faked, so it is covered on-device. Host tests drive the two
  // states reachable with an injected opener: loading and error.

  testWidgets('shows the loading state while the document opens', (
    tester,
  ) async {
    // An opener that never completes -> stays in loading.
    Future<PdfDocument> neverOpens(String _) => Completer<PdfDocument>().future;
    await tester.pumpWidget(
      localizedTestApp(
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
      localizedTestApp(
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
