import '../../l10n/l10n.dart';
import 'feedback_result.dart';

/// The localized snackbar message for each [FeedbackResult] (P14 SOC-3 — moved
/// out of the screen `build` so the mapping is reusable and unit-testable beside
/// the model). Resolution takes an [AppLocalizations] because the sealed switch
/// has no `BuildContext` of its own.
extension FeedbackResultL10n on FeedbackResult {
  String message(AppLocalizations l10n) => switch (this) {
    FeedbackSuccess() || FeedbackDuplicate() => l10n.feedbackSuccess,
    FeedbackRateLimited() => l10n.feedbackRateLimited,
    FeedbackRejectedUnverified() => l10n.feedbackRejectedUnverified,
    FeedbackOffline() => l10n.feedbackOffline,
    FeedbackInvalid() => l10n.feedbackInvalid,
    FeedbackServerError() => l10n.feedbackServerError,
  };
}
