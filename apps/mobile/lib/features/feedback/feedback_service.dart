import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'attestation_provider.dart';
import 'diagnostics.dart';
import 'feedback_config.dart';
import 'feedback_result.dart';

class FeedbackDraft {
  final String category;
  final String message;
  final String? email;
  final String? turnstileToken;
  const FeedbackDraft({
    required this.category,
    required this.message,
    this.email,
    this.turnstileToken,
  });
}

class FeedbackService {
  final FeedbackConfig config;
  final DiagnosticsCollector collector;
  final AttestationProvider attestation;
  final http.Client httpClient;

  /// Upper bound on each network POST. A stalled TCP connection never returns,
  /// so without this the submit spinner would hang forever; on timeout we fall
  /// back to the existing offline result.
  final Duration timeout;
  final String Function() _newId;

  FeedbackService({
    required this.config,
    required this.collector,
    required this.attestation,
    required this.httpClient,
    this.timeout = const Duration(seconds: 15),
    String Function()? newId,
  }) : _newId = newId ?? (() => const Uuid().v4());

  Future<FeedbackResult> submit(FeedbackDraft draft) async {
    try {
      final base = Uri.parse(config.workerUrl);

      // 1. One-time server-issued challenge (anti-replay for attestation).
      final chalRes = await httpClient
          .post(base.replace(path: '/challenge'))
          .timeout(timeout);
      if (chalRes.statusCode != 200) return const FeedbackServerError();
      // Defensive parse (P14 SF-2): a malformed body or absent/non-string
      // `challenge` yields a handled FeedbackServerError, consistent with the
      // response mapping below, instead of a bare cast throwing.
      final challenge = _json(chalRes)['challenge'];
      if (challenge is! String || challenge.isEmpty) {
        return const FeedbackServerError();
      }

      // 2. Attestation over the challenge; null → rely on Turnstile.
      final att = await attestation.attest(challenge);

      // 3. Diagnostics (non-personal only).
      final diag = await collector.collect();

      final payload = <String, dynamic>{
        'category': draft.category,
        'message': draft.message,
        if (draft.email != null && draft.email!.isNotEmpty)
          'email': draft.email,
        if (draft.turnstileToken != null)
          'turnstileToken': draft.turnstileToken,
        if (att != null) 'attestation': att.toJson(),
        'idempotencyKey': _newId(),
        'diagnostics': diag.toJson(),
      };

      // 4. Submit.
      final res = await httpClient
          .post(
            base.replace(path: '/feedback'),
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(timeout);
      return _map(res);
    } on TimeoutException {
      return const FeedbackOffline();
    } on http.ClientException {
      return const FeedbackOffline();
    } catch (_) {
      return const FeedbackServerError();
    }
  }

  FeedbackResult _map(http.Response res) {
    switch (res.statusCode) {
      case 201:
        return FeedbackSuccess(_url(res));
      case 200:
        final body = _json(res);
        return body['duplicate'] == true
            ? FeedbackDuplicate(_url(res))
            : FeedbackSuccess(_url(res));
      case 400:
        return const FeedbackInvalid();
      case 401:
        return const FeedbackRejectedUnverified();
      case 429:
        return const FeedbackRateLimited();
      default:
        return const FeedbackServerError();
    }
  }

  Map<String, dynamic> _json(http.Response res) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      return const {};
    }
  }

  String? _url(http.Response res) => _json(res)['issueUrl'] as String?;
}
