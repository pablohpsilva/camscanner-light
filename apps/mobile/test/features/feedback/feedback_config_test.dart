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
}
