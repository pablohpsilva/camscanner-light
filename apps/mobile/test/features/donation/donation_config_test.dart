import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_config.dart';

void main() {
  test('exposes kofiUrl and bitcoinAddress as strings', () {
    expect(DonationConfig.kofiUrl, isA<String>());
    expect(DonationConfig.bitcoinAddress, isA<String>());
  });

  test('defaults are empty (unconfigured) so no dead links ship', () {
    expect(DonationConfig.kofiUrl, '');
    expect(DonationConfig.bitcoinAddress, '');
  });
}
