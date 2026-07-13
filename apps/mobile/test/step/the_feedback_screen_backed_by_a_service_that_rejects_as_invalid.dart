import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

import '../features/feedback/_fakes.dart';

/// A [FeedbackService] stub whose [submit] always resolves to a fixed
/// [FeedbackResult] without any network I/O, so BDD steps can drive the
/// screen's result-message branches deterministically.
class BddStubFeedbackService extends FeedbackService {
  final FeedbackResult result;
  FeedbackDraft? lastDraft;

  BddStubFeedbackService(this.result)
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

/// Usage: the feedback screen backed by a service that rejects as invalid
///
/// Pushes [FeedbackScreen] onto a real navigator stack (rather than using it
/// as `home:`) so that tapping its back button has an observable effect:
/// [Navigator.maybePop] only does something when there is a route to pop.
Future<void> theFeedbackScreenBackedByAServiceThatRejectsAsInvalid(
  WidgetTester tester,
) async {
  final service = BddStubFeedbackService(const FeedbackInvalid());
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-feedback'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeedbackScreen(
                    dependencies: FeedbackDependencies(
                      createService: () => service,
                    ),
                  ),
                ),
              ),
              child: const Text('open feedback'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-feedback')));
  await tester.pumpAndSettle();
}
