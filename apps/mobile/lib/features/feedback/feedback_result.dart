sealed class FeedbackResult {
  const FeedbackResult();
}

class FeedbackSuccess extends FeedbackResult {
  final String? issueUrl;
  const FeedbackSuccess(this.issueUrl);
}

class FeedbackDuplicate extends FeedbackResult {
  final String? issueUrl;
  const FeedbackDuplicate(this.issueUrl);
}

class FeedbackRejectedUnverified extends FeedbackResult {
  const FeedbackRejectedUnverified();
}

class FeedbackRateLimited extends FeedbackResult {
  const FeedbackRateLimited();
}

class FeedbackInvalid extends FeedbackResult {
  const FeedbackInvalid();
}

class FeedbackOffline extends FeedbackResult {
  const FeedbackOffline();
}

class FeedbackServerError extends FeedbackResult {
  const FeedbackServerError();
}
