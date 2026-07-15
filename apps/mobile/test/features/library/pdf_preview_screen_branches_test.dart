// Branch coverage for PdfPreviewScreen: the successful-open path (lines
// 52-58, which flips to _loading=false / _error=false and builds the
// PdfViewPinch branch at lines 105/107), and the back button callback (line
// 82). A minimal in-memory PdfDocument/PdfPage/PdfPageTexture fake stands in
// for the native pdfx plugin so the loaded state is reachable on host.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:pdfx/pdfx.dart';

import '../../support/localized_app.dart';

class _FakeTexture extends PdfPageTexture {
  _FakeTexture() : super(id: 1, pageId: 'p1', pageNumber: 1);
  @override
  int? get textureWidth => 100;
  @override
  int? get textureHeight => 100;
  @override
  bool get hasUpdatedTexture => true;
  @override
  Future<void> dispose() async {}
  @override
  Future<bool> updateRect({
    required String documentId,
    int destinationX = 0,
    int destinationY = 0,
    int? width,
    int? height,
    int sourceX = 0,
    int sourceY = 0,
    int? textureWidth,
    int? textureHeight,
    double? fullWidth,
    double? fullHeight,
    String? backgroundColor,
    bool allowAntiAliasing = true,
  }) async => true;
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => 0;
}

class _FakePage extends PdfPage {
  _FakePage(PdfDocument doc)
    : super(
        document: doc,
        id: 'p1',
        pageNumber: 1,
        width: 100,
        height: 100,
        autoCloseAndroid: false,
      );
  @override
  Future<void> close() async {}
  @override
  Future<PdfPageImage?> render({
    required double width,
    required double height,
    PdfPageImageFormat format = PdfPageImageFormat.png,
    String? backgroundColor,
    Rect? cropRect,
    int quality = 100,
    bool forPrint = false,
    bool removeTempFile = true,
  }) async => null;
  @override
  Future<PdfPageTexture> createTexture() async => _FakeTexture();
}

class _FakeDoc extends PdfDocument {
  bool closed = false;
  _FakeDoc() : super(sourceName: 'fake', id: 'd1', pagesCount: 1);
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<PdfPage> getPage(
    int pageNumber, {
    bool autoCloseAndroid = false,
  }) async => _FakePage(this);
  @override
  bool operator ==(Object other) => identical(this, other);
  @override
  int get hashCode => 0;
}

void main() {
  testWidgets(
    'a successful open shows the PdfViewPinch (loaded) state, no error/loading',
    (tester) async {
      await tester.pumpWidget(
        localizedTestApp(
          home: PdfPreviewScreen(
            pdfPath: '/x/export.pdf',
            name: 'Lease Agreement',
            opener: (_) async => _FakeDoc(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byKey(const Key('pdf-preview-view')), findsOneWidget);
      expect(find.byKey(const Key('pdf-preview-loading')), findsNothing);
      expect(find.byKey(const Key('pdf-preview-error')), findsNothing);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, ReamColors.light.paper);

      // PdfViewPinch schedules a short-lived internal "real size overlay"
      // Timer on layout; drain it before the test ends so flutter_test's
      // pending-timer invariant check does not fail.
      await tester.pump(const Duration(milliseconds: 150));
    },
  );

  testWidgets('tapping the back button pops the loaded preview screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('push-pdf-preview'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PdfPreviewScreen(
                      pdfPath: '/x/export.pdf',
                      name: 'Lease Agreement',
                      opener: (_) async => _FakeDoc(),
                    ),
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-pdf-preview')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('pdf-preview-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ream-back')));
    await tester.pumpAndSettle();

    expect(find.byType(PdfPreviewScreen), findsNothing);
    expect(find.byKey(const Key('push-pdf-preview')), findsOneWidget);
  });

  testWidgets('tapping the back button pops the loading preview screen', (
    tester,
  ) async {
    // never-completing opener keeps the screen in the loading state so this
    // also proves the back button works from _loading (line 82 is shared by
    // both branches; this exercises the path already covered as "loading" in
    // pdf_preview_screen_test.dart, kept here for completeness of the pop).
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('push-pdf-loading'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PdfPreviewScreen(
                      pdfPath: '/x/export.pdf',
                      name: 'Lease Agreement',
                      opener: (_) => Completer<PdfDocument>().future,
                    ),
                  ),
                ),
                child: const Text('push'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('push-pdf-loading')));
    await tester.pump(); // dispatch tap, push the route
    await tester.pump(const Duration(milliseconds: 300)); // finish transition
    expect(find.byKey(const Key('pdf-preview-loading')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ream-back')));
    // Drain the pop transition in discrete frames (no pumpAndSettle: the
    // loading screen's CircularProgressIndicator ticks forever while mounted).
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(PdfPreviewScreen), findsNothing);
  });

  testWidgets(
    'when the screen is disposed before the opener resolves, the late document is closed',
    (tester) async {
      final opened = Completer<PdfDocument>();
      final doc = _FakeDoc();
      await tester.pumpWidget(
        MaterialApp(
          theme: ReamTheme.light(),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('push-pdf-slow'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfPreviewScreen(
                        pdfPath: '/x/export.pdf',
                        name: 'Lease Agreement',
                        opener: (_) => opened.future,
                      ),
                    ),
                  ),
                  child: const Text('push'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('push-pdf-slow')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('pdf-preview-loading')), findsOneWidget);

      // Pop the screen while the opener is still pending, THEN let it resolve
      // -> _open()'s `if (!mounted)` branch fires and closes the late doc.
      Navigator.of(tester.element(find.byType(PdfPreviewScreen))).pop();
      // Drain the pop transition in discrete frames (no pumpAndSettle: the
      // loading screen's CircularProgressIndicator ticks forever while mounted).
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.byType(PdfPreviewScreen), findsNothing);

      opened.complete(doc);
      await tester.pump();
      await tester.pump();

      expect(doc.closed, isTrue, reason: 'unmounted-late doc must be closed');
    },
  );
}
