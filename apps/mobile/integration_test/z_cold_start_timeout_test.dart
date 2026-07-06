// Cold-start usability gate. Boots the REAL app on a device and asserts the
// home library becomes USABLE within a hard budget — not just that a frame
// renders. "Opens but never loads" (a perpetual CircularProgressIndicator)
// fails here instead of hanging forever, because we poll with bounded pump()
// steps rather than pumpAndSettle() (which itself never settles on a spinner).
//
// Run: flutter test integration_test/z_cold_start_timeout_test.dart -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const budget = Duration(seconds: 10);
  const step = Duration(milliseconds: 100);

  testWidgets('cold start: home library is usable within 10s', (tester) async {
    final sw = Stopwatch()..start();
    app.main();

    // Poll for the home to finish loading. We consider the app "usable" once
    // the loading spinner is gone AND the Documents app bar is on screen.
    var loaded = false;
    while (sw.elapsed < budget) {
      await tester.pump(step);
      final stillLoading = find
          .byKey(const Key('documents-loading'))
          .evaluate()
          .isNotEmpty;
      final homeReady = find
          .widgetWithText(AppBar, 'Documents')
          .evaluate()
          .isNotEmpty;
      if (!stillLoading && homeReady) {
        loaded = true;
        break;
      }
    }
    sw.stop();

    final stillLoading = find
        .byKey(const Key('documents-loading'))
        .evaluate()
        .isNotEmpty;
    final onError = find
        .byKey(const Key('documents-error'))
        .evaluate()
        .isNotEmpty;

    expect(
      loaded,
      isTrue,
      reason:
          'App did not reach a usable Documents home within ${budget.inSeconds}s '
          '(elapsed ${sw.elapsedMilliseconds}ms). '
          'stillLoading=$stillLoading onError=$onError. '
          'A stuck spinner means createRepository()/listDocumentSummaries() '
          'never resolved.',
    );
  });
}
