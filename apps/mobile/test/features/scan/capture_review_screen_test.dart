import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';
import '../../support/fake_scan.dart';

// Detector whose result is controlled by a Completer — lets tests simulate
// detection arriving AFTER the user has interacted.
class _SlowDetector implements EdgeDetector {
  _SlowDetector(this._completer);
  final Completer<DetectionResult?> _completer;
  @override
  Future<DetectionResult?> detect(Uint8List bytes) => _completer.future;
}

// Detector that always throws, simulating an OpenCV / file-read error.
class _ThrowingDetector implements EdgeDetector {
  @override
  Future<DetectionResult?> detect(Uint8List bytes) async =>
      throw Exception('boom');
}

void main() {
  // IMPORTANT — use a NON-LOADABLE path on purpose. Routing a REAL file through
  // Image.file in a host widget test leaves a pending dart:io isolate-port read
  // that never resolves under flutter_test's fake-async, hanging the test (and
  // even a bare pump() does not save it — verified empirically). A bad path
  // errors fast (no pending I/O), so the test runs instantly. This asserts the
  // review screen's STRUCTURE + button wiring; real image rendering is verified
  // on-device by the A3 BDD integration test (where real async loads the file).
  testWidgets('shows the image area and Retake/Accept; callbacks fire',
      (tester) async {
    var retook = false;
    var accepted = false;

    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/capture.jpg'),
        onRetake: () => retook = true,
        onAccept: (corners) => accepted = true,
      ),
    ));
    await tester.pump();

    expect(find.widgetWithText(AppBar, 'Review'), findsOneWidget);
    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retake'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Accept'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-retake')));
    await tester.tap(find.byKey(const Key('review-accept')));
    expect(retook, isTrue);
    expect(accepted, isTrue);
  });

  testWidgets('saving disables buttons and shows the spinner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/x.jpg'),
        onRetake: () {},
        onAccept: (corners) {},
        saving: true,
      ),
    ));
    expect(find.byKey(const Key('review-saving')), findsOneWidget);
    final accept = tester.widget<FilledButton>(
        find.byKey(const Key('review-accept')));
    expect(accept.onPressed, isNull);
  });

  // ── New tests for the crop overlay integration (Task 5) ──────────────────

  CaptureReviewScreen subject({
    required ValueChanged<CropCorners> onAccept,
    VoidCallback? onRetake,
    bool saving = false,
    Future<Size> Function(String)? decode,
  }) =>
      CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/cap.jpg'),
        onRetake: onRetake ?? () {},
        onAccept: onAccept,
        saving: saving,
        decodeImageSize: decode ?? (_) async => const Size(1000, 750),
      );

  testWidgets('shows the crop overlay once the size resolves', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
  });

  testWidgets('shows the plain image (no overlay) before the size resolves',
      (tester) async {
    final never = Completer<Size>();
    await tester.pumpWidget(MaterialApp(
        home: subject(onAccept: (_) {}, decode: (_) => never.future)));
    await tester.pump(); // do not settle (would hang on the pending future)
    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.byKey(const Key('crop-overlay')), findsNothing);
  });

  testWidgets('Accept passes the current corners', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (c) => accepted = c)));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, isNotNull);
    expect(accepted!.topLeft.dx, greaterThan(0.0)); // moved from full-frame
  });

  testWidgets('Reset restores full-frame corners', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (c) => accepted = c)));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('saving disables the overlay and Reset', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (_) {}, saving: true)));
    // Use pump() not pumpAndSettle(): CircularProgressIndicator is indeterminate
    // and its animation controller never stops, so pumpAndSettle() always times out.
    await tester.pump(); // schedule decode microtask
    await tester.pump(); // apply setState(_imageSize)
    final reset = tester.widget<TextButton>(find.byKey(const Key('crop-reset')));
    expect(reset.onPressed, isNull);
  });

  testWidgets('decode failure falls back to the plain image; Accept still works',
      (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(
        home: subject(onAccept: (c) => accepted = c, decode: (_) async => throw 'boom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-overlay')), findsNothing);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('popping before the size resolves does not setState after dispose',
      (tester) async {
    final later = Completer<Size>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => subject(onAccept: (_) {}, decode: (_) => later.future))),
          child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    nav.currentState!.pop();          // leave the review screen
    await tester.pumpAndSettle();
    later.complete(const Size(1000, 750)); // resolver lands after dispose
    await tester.pump();
    expect(tester.takeException(), isNull); // no setState-after-dispose
  });

  // ── F2: detection + confidence cue ──────────────────────────────────────────

  const detectedCorners = CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  );

  const highResult = DetectionResult(corners: detectedCorners, confidence: 0.8);
  const lowResult  = DetectionResult(corners: detectedCorners, confidence: 0.3);

  // Wraps CaptureReviewScreen with injectable edge detector + readBytes so tests
  // run without real file I/O (FakeEdgeDetector ignores the bytes it receives).
  CaptureReviewScreen subjectWithDetector({
    EdgeDetector? edgeDetector,
    ValueChanged<CropCorners>? onAccept,
    VoidCallback? onRetake,
  }) =>
      CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/cap.jpg'),
        onRetake: onRetake ?? () {},
        onAccept: onAccept ?? (_) {},
        decodeImageSize: (_) async => const Size(1000, 750),
        readBytes: (_) async => Uint8List(0),   // bytes irrelevant; FakeEdgeDetector ignores them
        edgeDetector: edgeDetector,
      );

  testWidgets('detection result pre-fills corners on Accept', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subjectWithDetector(
      edgeDetector: FakeEdgeDetector(result: highResult),
      onAccept: (c) => accepted = c,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, detectedCorners);
  });

  testWidgets('confidence ≥ 0.5 → green overlay', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subjectWithDetector(
      edgeDetector: FakeEdgeDetector(result: highResult),
    )));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor,
      Colors.green,
    );
  });

  testWidgets('confidence < 0.5 → blue overlay', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subjectWithDetector(
      edgeDetector: FakeEdgeDetector(result: lowResult),
    )));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor,
      Colors.blue,
    );
  });

  testWidgets('null detection → full-frame corners, blue overlay', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subjectWithDetector(
      edgeDetector: FakeEdgeDetector(result: null),
      onAccept: (c) => accepted = c,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
    expect(
      tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor,
      Colors.blue,
    );
  });

  testWidgets('no edgeDetector → full-frame corners', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subjectWithDetector(
      edgeDetector: null,
      onAccept: (c) => accepted = c,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('late result discarded after user drags a handle', (tester) async {
    final completer = Completer<DetectionResult?>();
    await tester.pumpWidget(MaterialApp(home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: () {},
      onAccept: (_) {},
      decodeImageSize: (_) async => const Size(1000, 750),
      readBytes: (_) async => Uint8List(0),
      edgeDetector: _SlowDetector(completer),
    )));
    await tester.pumpAndSettle();
    // User drags a handle before detection completes.
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    // Now detection completes.
    completer.complete(highResult);
    await tester.pump();
    // Detected corners must NOT have replaced the dragged position.
    final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
    expect(overlay.corners, isNot(detectedCorners));
  });

  testWidgets('late result discarded after Reset', (tester) async {
    final completer = Completer<DetectionResult?>();
    await tester.pumpWidget(MaterialApp(home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: () {},
      onAccept: (_) {},
      decodeImageSize: (_) async => const Size(1000, 750),
      readBytes: (_) async => Uint8List(0),
      edgeDetector: _SlowDetector(completer),
    )));
    await tester.pumpAndSettle();
    // User taps Reset before detection completes.
    await tester.tap(find.byKey(const Key('crop-reset')));
    await tester.pumpAndSettle();
    // Now detection completes.
    completer.complete(highResult);
    await tester.pump();
    // Detected corners must NOT have overridden the reset-to-fullFrame.
    final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
    expect(overlay.corners, CropCorners.fullFrame);
  });

  testWidgets('detection throws → full-frame fallback, no crash', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: () {},
      onAccept: (c) => accepted = c,
      decodeImageSize: (_) async => const Size(1000, 750),
      readBytes: (_) async => Uint8List(0),
      edgeDetector: _ThrowingDetector(),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('readBytes throws → full-frame fallback, no crash', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: () {},
      onAccept: (c) => accepted = c,
      decodeImageSize: (_) async => const Size(1000, 750),
      readBytes: (_) async => throw Exception('no file'),
      edgeDetector: FakeEdgeDetector(result: highResult),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });
}
