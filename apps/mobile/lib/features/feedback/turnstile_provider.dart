/// The Turnstile token is produced by the on-screen Turnstile widget and passed
/// into the service at submit time. This holder keeps the service decoupled from
/// the widget package so host tests can supply a token directly.
class TurnstileResult {
  final String? token;
  const TurnstileResult(this.token);
}
