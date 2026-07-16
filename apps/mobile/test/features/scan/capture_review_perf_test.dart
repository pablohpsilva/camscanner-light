import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_scan.dart';
import '../../support/localized_app.dart';

/// P13 tasks 3+4: capture-review reads the source bytes ONCE and skips the
/// detection isolate when the user has already interacted.
void main() {
  Widget review({
    required FakeEdgeDetector detector,
    required Future<Uint8List> Function(String) readBytes,
  }) => localizedTestApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/cap.jpg'),
      onRetake: () {},
      onAccept: (_, _) {},
      enableCrop: true,
      edgeDetector: detector,
      readBytes: readBytes,
      decodeImageSize: (_) async => const Size(1000, 750),
    ),
  );

  testWidgets('PERF-1: the source JPEG is read off disk exactly once', (
    tester,
  ) async {
    var reads = 0;
    await tester.pumpWidget(
      review(
        detector: FakeEdgeDetector(),
        readBytes: (_) async {
          reads++;
          return Uint8List(0);
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(reads, 1, reason: 'initState + _runDetection share one read');
  });

  testWidgets('PERF-2: detection is skipped when the user interacts before the '
      'bytes resolve', (tester) async {
    final bytesGate = Completer<Uint8List>();
    final detector = FakeEdgeDetector();
    await tester.pumpWidget(
      review(detector: detector, readBytes: (_) => bytesGate.future),
    );
    // Size resolves → the crop overlay is shown; detection is awaiting bytes.
    await tester.pumpAndSettle();
    // User drags a handle before detection can start.
    await tester.drag(
      find.byKey(const Key('crop-handle-tl')),
      const Offset(40, 30),
    );
    await tester.pumpAndSettle();
    // Now the bytes arrive — detection must NOT run (user already interacted).
    bytesGate.complete(Uint8List(0));
    await tester.pumpAndSettle();
    expect(
      detector.calls,
      0,
      reason: 'skipped the ~5s isolate after interaction',
    );
  });

  testWidgets('the untouched path still runs detection once', (tester) async {
    final detector = FakeEdgeDetector();
    await tester.pumpWidget(
      review(detector: detector, readBytes: (_) async => Uint8List(0)),
    );
    await tester.pumpAndSettle();
    expect(detector.calls, 1);
  });
}
