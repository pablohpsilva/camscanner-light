/// Ship-safe configuration for the feedback feature. Both values are public:
/// the Worker URL and the Turnstile *site* key (not the secret).
class FeedbackConfig {
  final String workerUrl;
  final String turnstileSiteKey;

  const FeedbackConfig({
    required this.workerUrl,
    required this.turnstileSiteKey,
  });

  factory FeedbackConfig.fromEnvironment() => const FeedbackConfig(
    workerUrl: String.fromEnvironment('FEEDBACK_WORKER_URL'),
    turnstileSiteKey: String.fromEnvironment('TURNSTILE_SITE_KEY'),
  );

  bool get isConfigured => workerUrl.isNotEmpty && turnstileSiteKey.isNotEmpty;
}
