import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import 'attestation_provider.dart';
import 'diagnostics.dart';
import 'feedback_availability.dart';
import 'feedback_config.dart';
import 'feedback_service.dart';

typedef FeedbackServiceFactory = FeedbackService Function();
typedef FeedbackAvailabilityFactory = FeedbackAvailability Function();

AppLogger _defaultLogger() => const PrintAppLogger();

/// Composition root for the Feedback feature (parallel to LibraryDependencies).
///
/// Production builds a [FeedbackService] wired with platform implementations.
/// Tests inject a [createService] override to supply fakes without touching
/// production constructors.
class FeedbackDependencies {
  final FeedbackConfig config;
  final AppLogger Function() logger;
  final FeedbackServiceFactory? _createService;
  final FeedbackAvailabilityFactory? _createAvailability;

  const FeedbackDependencies({
    this.config = FeedbackConfig.fromEnvironment,
    this.logger = _defaultLogger,
    // Named createService/createAvailability (not this._createService) so the
    // public constructor API keeps those names; the fields are deliberately
    // private (only service()/availability() expose the built collaborator).
    FeedbackServiceFactory? createService,
    FeedbackAvailabilityFactory? createAvailability,
  }) : _createService = createService, // ignore: prefer_initializing_formals
       // ignore: prefer_initializing_formals
       _createAvailability = createAvailability;

  FeedbackService service() =>
      _createService?.call() ??
      FeedbackService(
        config: config,
        collector: const PlatformDiagnosticsCollector(),
        attestation: const PlatformAttestationProvider(),
        httpClient: http.Client(),
      );

  FeedbackAvailability availability() =>
      _createAvailability?.call() ??
      HttpFeedbackAvailability(config: config, httpClient: http.Client());
}
