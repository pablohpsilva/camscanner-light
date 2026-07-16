import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_config.dart';

void main() {
  test('isConfigured is false when the worker url is empty', () {
    const c = FeedbackConfig(workerUrl: '', turnstileSiteKey: 'k');
    expect(c.isConfigured, isFalse);
  });
  test('isConfigured is true when both values are present', () {
    const c = FeedbackConfig(workerUrl: 'https://w', turnstileSiteKey: 'k');
    expect(c.isConfigured, isTrue);
  });

  group('turnstileOrigin', () {
    test('is scheme://host of the worker url (drops path/port-less)', () {
      const c = FeedbackConfig(
        workerUrl: 'https://fb.example.com/api/feedback',
        turnstileSiteKey: 'k',
      );
      expect(c.turnstileOrigin, 'https://fb.example.com');
    });
    test('falls back to https://localhost when the worker url is empty', () {
      const c = FeedbackConfig(workerUrl: '', turnstileSiteKey: 'k');
      expect(c.turnstileOrigin, 'https://localhost');
    });
  });

  test('fromEnvironment is a const FeedbackConfig usable as a default', () {
    // A const static (not a factory) — reachable without parens and const.
    const FeedbackConfig cfg = FeedbackConfig.fromEnvironment;
    expect(cfg, isA<FeedbackConfig>());
  });
}
