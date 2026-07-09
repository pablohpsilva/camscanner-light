import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/feedback/feedback_availability.dart';
import 'package:mobile/features/feedback/feedback_config.dart';

import '_fakes.dart';

void main() {
  group('HttpFeedbackAvailability', () {
    test('200 response → isAvailable() returns true and path is /health',
        () async {
      Uri? capturedUri;
      final client = MockClient((req) async {
        capturedUri = req.url;
        return http.Response('{"ok":true}', 200);
      });

      final availability = HttpFeedbackAvailability(
        config: testFeedbackConfig,
        httpClient: client,
      );

      expect(await availability.isAvailable(), isTrue);
      expect(capturedUri?.path, equals('/health'));
    });

    test('503 response → isAvailable() returns false', () async {
      final client = MockClient(
        (_) async => http.Response('Service Unavailable', 503),
      );

      final availability = HttpFeedbackAvailability(
        config: testFeedbackConfig,
        httpClient: client,
      );

      expect(await availability.isAvailable(), isFalse);
    });

    test('ClientException → isAvailable() returns false', () async {
      final client = MockClient(
        (_) async => throw http.ClientException('network error'),
      );

      final availability = HttpFeedbackAvailability(
        config: testFeedbackConfig,
        httpClient: client,
      );

      expect(await availability.isAvailable(), isFalse);
    });

    test('timeout → isAvailable() returns false', () async {
      final client = MockClient((_) async {
        // Delay longer than the configured timeout.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        return http.Response('{"ok":true}', 200);
      });

      final availability = HttpFeedbackAvailability(
        config: testFeedbackConfig,
        httpClient: client,
        timeout: const Duration(milliseconds: 50),
      );

      expect(await availability.isAvailable(), isFalse);
    });

    test(
      'unconfigured config → isAvailable() returns false without HTTP request',
      () async {
        var requestMade = false;
        final client = MockClient((_) async {
          requestMade = true;
          return http.Response('{"ok":true}', 200);
        });

        const unconfigured = FeedbackConfig(workerUrl: '', turnstileSiteKey: '');
        final availability = HttpFeedbackAvailability(
          config: unconfigured,
          httpClient: client,
        );

        expect(await availability.isAvailable(), isFalse);
        expect(requestMade, isFalse, reason: 'No HTTP request should be made when unconfigured');
      },
    );
  });
}
