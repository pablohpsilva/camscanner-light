import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:mobile/features/feedback/attestation_provider.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/feedback/feedback_screen.dart';
import 'package:mobile/features/feedback/feedback_service.dart';

import '../features/feedback/_fakes.dart';
import '../support/localized_app.dart';

/// An [http.Client] whose every request hangs forever: it returns a Future
/// backed by a [Completer] that is never completed, modelling a TCP connection
/// that accepts but never responds (a stalled network).
class _StalledHttpClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return Completer<http.StreamedResponse>().future;
  }
}

/// Usage: the feedback screen backed by a stalled service
///
/// Injects a [FeedbackService] whose HTTP client never responds, paired with a
/// tiny [FeedbackService.timeout] so the submit's per-POST timeout fires almost
/// immediately and the screen falls back to its offline result — proving the
/// submit spinner clears even when the network stalls.
///
/// Mirrors `theFeedbackScreenBackedByAServiceThatRejectsAsInvalid`: the screen
/// is pushed onto a real navigator stack via an opener button.
Future<void> theFeedbackScreenBackedByAStalledService(
  WidgetTester tester,
) async {
  final service = FeedbackService(
    config: testFeedbackConfig,
    collector: const FakeDiagnosticsCollector(),
    attestation: const NoAttestationProvider(),
    httpClient: _StalledHttpClient(),
    timeout: const Duration(milliseconds: 50),
  );
  await tester.pumpWidget(
    localizedTestApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              key: const Key('open-feedback'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => FeedbackScreen(
                    dependencies: FeedbackDependencies(
                      createService: () => service,
                    ),
                  ),
                ),
              ),
              child: const Text('open feedback'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-feedback')));
  await tester.pumpAndSettle();
}
