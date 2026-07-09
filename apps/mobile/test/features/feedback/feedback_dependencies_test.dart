import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

import '_fakes.dart';

void main() {
  test('default deps expose a FeedbackService factory', () {
    const deps = FeedbackDependencies();
    expect(deps.service(), isA<FeedbackService>());
  });

  test('a test override factory is used', () {
    var called = false;
    final deps = FeedbackDependencies(
      createService: () {
        called = true;
        return FeedbackService(
          config: testFeedbackConfig,
          collector: const FakeDiagnosticsCollector(),
          attestation: const NoAttestationProvider(),
          httpClient: fakeHttpClient(),
        );
      },
    );
    deps.service();
    expect(called, isTrue);
  });
}
