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
          // Long timeout so the spinner is genuinely up mid-open; we still
          // drain the pending timeout timer at the end so none leaks.
          openTimeout: const Duration(seconds: 30),
        ),
      ),
    );
    await tester.pump(); // one frame; do NOT settle (opener never completes)
    expect(find.byKey(const Key('pdf-preview-loading')), findsOneWidget);
    // Drain the injected open timeout so the test leaves no pending timer.
    await tester.pump(const Duration(seconds: 31));
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

  testWidgets('clears the spinner once a fast opener completes', (
    tester,
  ) async {
    var opened = false;
    Future<PdfDocument> opensFast(String _) async {
      opened = true;
      throw Exception('no native document available in host');
    }

    await tester.pumpWidget(
      localizedTestApp(
        home: PdfPreviewScreen(
          pdfPath: '/x/export.pdf',
          name: 'Scan',
          opener: opensFast,
        ),
      ),
    );
    await tester.pumpAndSettle();
    // opener ran and the spinner cleared (success path resolves synchronously
    // fast; a real PdfDocument can only be exercised on-device).
    expect(opened, isTrue);
    expect(find.byKey(const Key('pdf-preview-loading')), findsNothing);
  });

  testWidgets('routes into the error state when the opener never returns', (
    tester,
  ) async {
    // An opener whose Future NEVER completes must not spin forever: the
    // injected openTimeout fires and routes into the existing error state.
    Future<PdfDocument> neverOpens(String _) => Completer<PdfDocument>().future;
    await tester.pumpWidget(
      localizedTestApp(
        home: PdfPreviewScreen(
          pdfPath: '/x/export.pdf',
          name: 'Scan',
          opener: neverOpens,
          openTimeout: const Duration(milliseconds: 50),
        ),
      ),
    );
    await tester.pump(); // initial frame -> loading
    await tester.pump(const Duration(milliseconds: 100)); // past the timeout
    expect(find.byKey(const Key('pdf-preview-loading')), findsNothing);
    expect(find.byKey(const Key('pdf-preview-error')), findsOneWidget);
  });
}
