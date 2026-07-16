/// Ship-safe configuration for the feedback feature. Both values are public:
/// the Worker URL and the Turnstile *site* key (not the secret).
class FeedbackConfig {
  final String workerUrl;
  final String turnstileSiteKey;

  const FeedbackConfig({
    required this.workerUrl,
    required this.turnstileSiteKey,
  });

  /// The single source for the build-time env config (P14 DUP-4). A `static
  /// const` — not a `factory` — so it is usable as a const default parameter,
  /// letting `FeedbackDependencies` reference it instead of re-inlining the two
  /// `String.fromEnvironment` reads.
  static const FeedbackConfig fromEnvironment = FeedbackConfig(
    workerUrl: String.fromEnvironment('FEEDBACK_WORKER_URL'),
    turnstileSiteKey: String.fromEnvironment('TURNSTILE_SITE_KEY'),
  );

  bool get isConfigured => workerUrl.isNotEmpty && turnstileSiteKey.isNotEmpty;

  /// The `scheme://host` origin of [workerUrl] (P14 SOC-4) for the Turnstile
  /// WebView's baseUrl — computed here once instead of in a per-rebuild IIFE in
  /// the screen. Falls back to `https://localhost` when unconfigured (empty
  /// [workerUrl], e.g. host tests).
  String get turnstileOrigin {
    if (workerUrl.isEmpty) return 'https://localhost';
    final u = Uri.parse(workerUrl);
    return '${u.scheme}://${u.host}';
  }
}
