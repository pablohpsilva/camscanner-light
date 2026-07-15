import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the feedback submit control is enabled again
///
/// After a stalled submit times out, `_submitting` must return to false: the
/// keyed submit control renders the interactive button again (not the progress
/// spinner). We assert the spinner is gone and the control is tappable.
///
/// Uses explicit [WidgetTester.pump] past the 50ms timeout bound rather than
/// `pumpAndSettle`, which would spin on the submit spinner while it is showing.
/// A final long pump drains the result SnackBar's auto-dismiss timer so no
/// pending-timer warning fires when the test ends.
Future<void> theFeedbackSubmitControlIsEnabledAgain(
  WidgetTester tester,
) async {
  // Advance past the 50ms per-POST timeout so submit() resolves to offline
  // and the finally-block clears the _submitting flag.
  await tester.pump(const Duration(milliseconds: 100));

  final submit = find.byKey(const Key('feedback-submit'));
  expect(submit, findsOneWidget);
  // The spinner branch is gone: no CircularProgressIndicator under the control.
  expect(
    find.descendant(
      of: submit,
      matching: find.byType(CircularProgressIndicator),
    ),
    findsNothing,
  );
  // Control is enabled again: tapping it re-triggers a submit without error.
  await tester.tap(submit, warnIfMissed: false);
  await tester.pump();

  // Drain the SnackBar auto-dismiss timer(s) so the test leaves no pending
  // timers. The stalled client never completes, so only advance the fake
  // clock; the second submit's own 50ms timeout also elapses here.
  await tester.pump(const Duration(seconds: 6));
}
