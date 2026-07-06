/// Configuration constants for the donation feature, injected at build time via
/// `--dart-define` (or `--dart-define-from-file`) so no Ko-fi URL or Bitcoin
/// address ever lives in source or git history. An unset value resolves to an
/// empty string — "not configured" — and the UI hides the corresponding section
/// so no dead link ever ships.
///
/// Provide values locally with a gitignored `donation_config.json`:
///   flutter run --dart-define-from-file=donation_config.json
/// (see `donation_config.example.json` for the expected keys). The release
/// build scripts pass this file automatically when it is present.
///
/// These are the ONLY place donation values live. Do not hardcode a Ko-fi URL
/// or BTC address anywhere else.
class DonationConfig {
  const DonationConfig._();

  /// Ko-fi donation page, opened in the external browser.
  /// Set via `--dart-define=KOFI_URL=https://ko-fi.com/yourname`.
  static const String kofiUrl = String.fromEnvironment('KOFI_URL');

  /// Bitcoin address (display-only: shown as a BIP-21 QR + copyable text).
  /// Set via `--dart-define=BITCOIN_ADDRESS=bc1q...`.
  static const String bitcoinAddress =
      String.fromEnvironment('BITCOIN_ADDRESS');
}
