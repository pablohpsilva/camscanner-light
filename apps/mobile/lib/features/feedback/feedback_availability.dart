import 'package:http/http.dart' as http;

import 'feedback_config.dart';

abstract class FeedbackAvailability {
  Future<bool> isAvailable();
}

/// Probes GET {workerUrl}/health. Returns true only on HTTP 200 within the
/// timeout. Returns false (silently) when unconfigured, on any non-200,
/// timeout, or error.
class HttpFeedbackAvailability implements FeedbackAvailability {
  final FeedbackConfig config;
  final http.Client httpClient;
  final Duration timeout;

  const HttpFeedbackAvailability({
    required this.config,
    required this.httpClient,
    this.timeout = const Duration(seconds: 3),
  });

  @override
  Future<bool> isAvailable() async {
    if (!config.isConfigured) return false; // no HTTP when unconfigured
    try {
      final uri = Uri.parse(config.workerUrl).replace(path: '/health');
      final res = await httpClient.get(uri).timeout(timeout);
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
