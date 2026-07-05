/// Swap-later constants for the donation feature. Fill these in when the
/// Ko-fi page and Bitcoin wallet exist. An empty string means "not configured
/// yet" — the UI hides the corresponding section so no dead link ever ships.
///
/// These are the ONLY place donation values live. Do not hardcode a Ko-fi URL
/// or BTC address anywhere else.
class DonationConfig {
  const DonationConfig._();

  // TODO: set your Ko-fi page, e.g. 'https://ko-fi.com/yourname'.
  static const String kofiUrl = '';

  // TODO: set your Bitcoin address, e.g. 'bc1q...'.
  static const String bitcoinAddress = '';
}
