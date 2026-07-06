import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_config.dart';

void main() {
  test('exposes kofiUrl and bitcoinAddress as strings', () {
    expect(DonationConfig.kofiUrl, isA<String>());
    expect(DonationConfig.bitcoinAddress, isA<String>());
  });

  test('defaults to empty when no --dart-define is supplied', () {
    // `flutter test` runs without the donation dart-defines, so the values
    // resolve to '' — which drives the UI's "unconfigured → hidden" behavior
    // and guarantees no address or URL is ever baked into source/history.
    expect(DonationConfig.kofiUrl, '');
    expect(DonationConfig.bitcoinAddress, '');
  });
}
