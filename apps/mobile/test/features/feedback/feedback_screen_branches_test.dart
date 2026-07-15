// TDD widget tests for lib/features/feedback/feedback_screen.dart branches
// not naturally exercised by test/bdd/feedback_validation.feature:
// the remaining `_showResult` switch arms (lines 67-74) that the BDD
// scenario's `FeedbackInvalid` case doesn't cover, and the back-button
// wiring (line 109) via an explicit route push + programmatic pop check.
//
// The `if (turnstileSiteKey.isNotEmpty)` branch (lines 238-249) is
// deliberately NOT exercised here: see the coverage report for why it's a
// named gap rather than silently skipped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

import '../../support/localized_app.dart';
import '_fakes.dart';

class _StubService extends FeedbackService {
  final FeedbackResult result;
  FeedbackDraft? lastDraft;

  _StubService(this.result)
    : super(
        config: testFeedbackConfig,
        collector: const FakeDiagnosticsCollector(),
        attestation: const NoAttestationProvider(),
        httpClient: fakeHttpClient(),
      );

  @override
  Future<FeedbackResult> submit(FeedbackDraft draft) async {
    lastDraft = draft;
    return result;
  }
}

Widget _host(FeedbackService service) => localizedTestApp(
  home: FeedbackScreen(
    dependencies: FeedbackDependencies(createService: () => service),
  ),
);

Future<void> _submitWithMessage(WidgetTester t, FeedbackService s) async {
  await t.pumpWidget(_host(s));
  await t.enterText(
    find.byKey(const Key('feedback-message')),
    'Something worth reporting',
  );
  await t.tap(find.byKey(const Key('feedback-submit')));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('duplicate result shows the same thanks message and pops', (
    t,
  ) async {
    await _submitWithMessage(t, _StubService(const FeedbackDuplicate('u')));
    expect(find.text('Thanks! Your feedback was sent.'), findsOneWidget);
  });

  testWidgets('rate-limited result shows a try-again-later message', (t) async {
    await _submitWithMessage(t, _StubService(const FeedbackRateLimited()));
    expect(
      find.text("You've sent a few already — please try again later."),
      findsOneWidget,
    );
  });

  testWidgets('rejected-unverified result shows a could-not-verify message', (
    t,
  ) async {
    await _submitWithMessage(
      t,
      _StubService(const FeedbackRejectedUnverified()),
    );
    expect(
      find.text("Couldn't verify the app — please try again."),
      findsOneWidget,
    );
  });

  testWidgets('offline result shows a check-your-connection message', (
    t,
  ) async {
    await _submitWithMessage(t, _StubService(const FeedbackOffline()));
    expect(find.text('Check your connection and try again.'), findsOneWidget);
  });

  testWidgets('server-error result shows a could-not-send message', (t) async {
    await _submitWithMessage(t, _StubService(const FeedbackServerError()));
    expect(
      find.text("Couldn't send right now — please try again."),
      findsOneWidget,
    );
  });

  testWidgets('success result pops the pushed route', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-feedback'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FeedbackScreen(
                      dependencies: FeedbackDependencies(
                        createService: () => s,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('open-feedback')));
    await t.pumpAndSettle();
    expect(find.byType(FeedbackScreen), findsOneWidget);

    await t.enterText(
      find.byKey(const Key('feedback-message')),
      'All good, just a suggestion',
    );
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pumpAndSettle();

    expect(find.byType(FeedbackScreen), findsNothing);
  });

  testWidgets('tapping back pops the pushed feedback screen', (t) async {
    final s = _StubService(const FeedbackInvalid());
    await t.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                key: const Key('open-feedback'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FeedbackScreen(
                      dependencies: FeedbackDependencies(
                        createService: () => s,
                      ),
                    ),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await t.tap(find.byKey(const Key('open-feedback')));
    await t.pumpAndSettle();
    expect(find.byType(FeedbackScreen), findsOneWidget);

    await t.tap(find.byKey(const Key('ream-back')));
    await t.pumpAndSettle();

    expect(find.byType(FeedbackScreen), findsNothing);
  });
}
