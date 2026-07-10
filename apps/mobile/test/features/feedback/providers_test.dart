import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';

class _Fake implements AttestationProvider {
  final Attestation? result;
  _Fake(this.result);
  @override
  Future<Attestation?> attest(String challenge) async => result;
}

void main() {
  test('a provider can return an attestation carrying the challenge', () async {
    final p = _Fake(
      const Attestation(
        platform: 'ios',
        token: 't',
        challenge: 'c',
        keyId: 'k',
      ),
    );
    final a = await p.attest('c');
    expect(a!.challenge, 'c');
    expect(a.platform, 'ios');
  });
  test('a provider returns null when attestation is unavailable', () async {
    final p = _Fake(null);
    expect(await p.attest('c'), isNull);
  });
}
