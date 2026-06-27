import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

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
        onAccept: () => accepted = true,
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
}
