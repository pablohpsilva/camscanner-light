import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_result.dart';
import 'package:mobile/features/feedback/feedback_result_l10n.dart';

import '../../support/localized_app.dart';

/// P14 SOC-3: the FeedbackResult → l10n message mapping, now an extension beside
/// the model, is unit-testable without the screen.
void main() {
  testWidgets('each result maps to its localized message', (tester) async {
    late AppLocalizations l10n;
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) {
            l10n = context.l10n;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(const FeedbackSuccess('u').message(l10n), l10n.feedbackSuccess);
    expect(const FeedbackDuplicate('u').message(l10n), l10n.feedbackSuccess);
    expect(const FeedbackRateLimited().message(l10n), l10n.feedbackRateLimited);
    expect(
      const FeedbackRejectedUnverified().message(l10n),
      l10n.feedbackRejectedUnverified,
    );
    expect(const FeedbackOffline().message(l10n), l10n.feedbackOffline);
    expect(const FeedbackInvalid().message(l10n), l10n.feedbackInvalid);
    expect(const FeedbackServerError().message(l10n), l10n.feedbackServerError);
  });
}
