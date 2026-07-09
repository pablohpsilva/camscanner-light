import 'package:http/http.dart' as http;

import 'attestation_provider.dart';
import 'diagnostics.dart';
import 'feedback_config.dart';
import 'feedback_service.dart';

typedef FeedbackServiceFactory = FeedbackService Function();

/// Composition root for the Feedback feature (parallel to LibraryDependencies).
///
/// Production builds a [FeedbackService] wired with platform implementations.
/// Tests inject a [createService] override to supply fakes without touching
/// production constructors.
class FeedbackDependencies {
  final FeedbackConfig config;
  final FeedbackServiceFactory? _createService;

  const FeedbackDependencies({
    this.config = const FeedbackConfig(
      workerUrl: String.fromEnvironment('FEEDBACK_WORKER_URL'),
      turnstileSiteKey: String.fromEnvironment('TURNSTILE_SITE_KEY'),
    ),
    this._createService,
  });

  FeedbackService service() =>
      _createService?.call() ??
      FeedbackService(
        config: config,
        collector: const PlatformDiagnosticsCollector(),
        attestation: const PlatformAttestationProvider(),
        httpClient: http.Client(),
      );
}
