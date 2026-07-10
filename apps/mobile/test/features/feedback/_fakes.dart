import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/feedback/diagnostics.dart';
import 'package:mobile/features/feedback/feedback_config.dart';

/// Shared test doubles for the feedback feature.
/// Imported by feedback_service_test.dart and feedback_dependencies_test.dart.

/// A [DiagnosticsCollector] that always returns a fixed [Diagnostics] snapshot.
class FakeDiagnosticsCollector implements DiagnosticsCollector {
  const FakeDiagnosticsCollector();

  @override
  Future<Diagnostics> collect() async => const Diagnostics(
    appVersion: '1.0.0',
    build: '42',
    os: 'iOS 18.3',
    device: 'iPhone15,2',
    locale: 'en_US',
  );
}

/// A no-op [http.Client] that returns `{}` with status 200 for every request.
http.Client fakeHttpClient() =>
    MockClient((req) async => http.Response('{}', 200));

/// A [FeedbackConfig] with deterministic values suitable for tests.
const testFeedbackConfig = FeedbackConfig(
  workerUrl: 'https://worker.test',
  turnstileSiteKey: 'test-site-key',
);
