import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/diagnostics.dart';
import 'package:mobile/features/feedback/feedback_config.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

class _FakeCollector implements DiagnosticsCollector {
  @override
  Future<Diagnostics> collect() async => const Diagnostics(
    appVersion: '1.0.0',
    build: '42',
    os: 'iOS 18.3',
    device: 'iPhone15,2',
    locale: 'en_US',
  );
}

const _config = FeedbackConfig(
  workerUrl: 'https://worker.test',
  turnstileSiteKey: 'sk',
);
const _draft = FeedbackDraft(
  category: 'bug',
  message: 'It crashed',
  email: 'u@e.com',
  turnstileToken: 'ts',
);

FeedbackService _service(
  MockClient client, {
  AttestationProvider attestation = const NoAttestationProvider(),
}) => FeedbackService(
  config: _config,
  collector: _FakeCollector(),
  attestation: attestation,
  httpClient: client,
  newId: () => '55555555-5555-5555-5555-555555555555',
);

void main() {
  test(
    'fetches a challenge then posts feedback; 201 → success with issueUrl',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((req) async {
        requests.add(req);
        if (req.url.path == '/challenge') {
          return http.Response(jsonEncode({'challenge': 'CHAL'}), 200);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['category'], 'bug');
        expect(body['turnstileToken'], 'ts');
        expect(body['idempotencyKey'], '55555555-5555-5555-5555-555555555555');
        expect(body['diagnostics']['device'], 'iPhone15,2');
        return http.Response(
          jsonEncode({
            'ok': true,
            'issueUrl': 'https://github.com/x/y/issues/3',
          }),
          201,
        );
      });
      final r = await _service(client).submit(_draft);
      expect(r, isA<FeedbackSuccess>());
      expect((r as FeedbackSuccess).issueUrl, contains('/issues/3'));
      expect(requests.first.url.path, '/challenge'); // challenge first
    },
  );

  test('includes attestation when the provider returns one', () async {
    Map<String, dynamic>? posted;
    final client = MockClient((req) async {
      if (req.url.path == '/challenge') {
        return http.Response(jsonEncode({'challenge': 'CHAL'}), 200);
      }
      posted = jsonDecode(req.body) as Map<String, dynamic>;
      return http.Response(jsonEncode({'ok': true, 'issueUrl': 'u'}), 201);
    });
    final attest = _StubAttest(
      const Attestation(
        platform: 'ios',
        token: 'attTok',
        challenge: 'CHAL',
        keyId: 'kid',
      ),
    );
    await _service(client, attestation: attest).submit(_draft);
    expect(posted!['attestation']['token'], 'attTok');
    expect(posted!['attestation']['challenge'], 'CHAL');
  });

  test('maps status codes to results', () async {
    Future<FeedbackResult> withStatus(int code, String body) {
      final client = MockClient((req) async {
        if (req.url.path == '/challenge') {
          return http.Response(jsonEncode({'challenge': 'C'}), 200);
        }
        return http.Response(body, code);
      });
      return _service(client).submit(_draft);
    }

    expect(
      await withStatus(
        200,
        jsonEncode({'ok': true, 'duplicate': true, 'issueUrl': 'u'}),
      ),
      isA<FeedbackDuplicate>(),
    );
    expect(await withStatus(400, '{}'), isA<FeedbackInvalid>());
    expect(await withStatus(401, '{}'), isA<FeedbackRejectedUnverified>());
    expect(await withStatus(429, '{}'), isA<FeedbackRateLimited>());
    expect(await withStatus(502, '{}'), isA<FeedbackServerError>());
  });

  test('malformed /challenge (missing field) → server error, does not throw', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/challenge') {
        return http.Response(jsonEncode({'not_challenge': 'x'}), 200);
      }
      return http.Response(jsonEncode({'ok': true, 'issueUrl': 'u'}), 201);
    });
    expect(await _service(client).submit(_draft), isA<FeedbackServerError>());
  });

  test('non-JSON /challenge body → server error, does not throw', () async {
    final client = MockClient((req) async {
      if (req.url.path == '/challenge') return http.Response('not json', 200);
      return http.Response(jsonEncode({'ok': true, 'issueUrl': 'u'}), 201);
    });
    expect(await _service(client).submit(_draft), isA<FeedbackServerError>());
  });

  test('network failure → offline', () async {
    final client = MockClient(
      (req) async => throw http.ClientException('no net'),
    );
    expect(await _service(client).submit(_draft), isA<FeedbackOffline>());
  });

  test('a stalled /challenge POST times out → offline', () async {
    final client = _StallingClient(stallPath: '/challenge');
    final service = FeedbackService(
      config: _config,
      collector: _FakeCollector(),
      attestation: const NoAttestationProvider(),
      httpClient: client,
      newId: () => '55555555-5555-5555-5555-555555555555',
      timeout: const Duration(milliseconds: 50),
    );
    expect(await service.submit(_draft), isA<FeedbackOffline>());
  });

  test('a stalled /feedback POST times out → offline', () async {
    final client = _StallingClient(stallPath: '/feedback');
    final service = FeedbackService(
      config: _config,
      collector: _FakeCollector(),
      attestation: const NoAttestationProvider(),
      httpClient: client,
      newId: () => '55555555-5555-5555-5555-555555555555',
      timeout: const Duration(milliseconds: 50),
    );
    expect(await service.submit(_draft), isA<FeedbackOffline>());
  });
}

/// An [http.Client] that never completes a POST to [stallPath] (simulates a
/// wedged TCP connection), while answering the other endpoint normally so the
/// flow can reach the stalling one.
class _StallingClient extends http.BaseClient {
  final String stallPath;
  _StallingClient({required this.stallPath});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (request.url.path == stallPath) {
      return Completer<http.StreamedResponse>().future; // never completes
    }
    // The non-stalling endpoint answers with a valid challenge so the flow
    // proceeds to the /feedback POST.
    final body = utf8.encode(jsonEncode({'challenge': 'CHAL'}));
    return Future.value(
      http.StreamedResponse(Stream.value(body), 200),
    );
  }
}

class _StubAttest implements AttestationProvider {
  final Attestation a;
  _StubAttest(this.a);
  @override
  Future<Attestation?> attest(String challenge) async => a;
}
