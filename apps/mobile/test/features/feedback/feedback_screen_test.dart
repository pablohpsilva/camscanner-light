import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

import '_fakes.dart';

class _StubService extends FeedbackService {
  FeedbackResult result;
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

Widget _host(FeedbackService service) => MaterialApp(
      home: FeedbackScreen(
        dependencies: FeedbackDependencies(createService: () => service),
      ),
    );

void main() {
  testWidgets('blocks submit when the message is empty', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pump();
    expect(s.lastDraft, isNull); // never submitted
    expect(find.text('Please enter a message'), findsOneWidget);
  });

  testWidgets('shows the public-visibility warning next to the email field',
      (t) async {
    await t.pumpWidget(_host(_StubService(const FeedbackSuccess('u'))));
    expect(find.byKey(const Key('feedback-email-warning')), findsOneWidget);
    expect(find.text('Optional. This will be publicly visible on GitHub.'),
        findsOneWidget);
  });

  testWidgets('rejects a malformed email', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.enterText(find.byKey(const Key('feedback-message')), 'hello');
    await t.enterText(find.byKey(const Key('feedback-email')), 'not-an-email');
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pump();
    expect(s.lastDraft, isNull);
    expect(find.text('Enter a valid email or leave it blank'), findsOneWidget);
  });

  testWidgets('submits a valid message and shows success', (t) async {
    final s = _StubService(const FeedbackSuccess('u'));
    await t.pumpWidget(_host(s));
    await t.enterText(
        find.byKey(const Key('feedback-message')), 'Great app, one bug');
    await t.tap(find.byKey(const Key('feedback-submit')));
    await t.pumpAndSettle();
    expect(s.lastDraft!.message, 'Great app, one bug');
    expect(find.text('Thanks! Your feedback was sent.'), findsOneWidget);
  });

  testWidgets('toggling diagnostics reveals the preview', (t) async {
    await t.pumpWidget(_host(_StubService(const FeedbackSuccess('u'))));
    expect(find.textContaining('Diagnostics attached'), findsNothing);
    await t.tap(find.byKey(const Key('feedback-diagnostics-toggle')));
    await t.pumpAndSettle();
    expect(find.textContaining('Diagnostics attached'), findsOneWidget);
  });
}
