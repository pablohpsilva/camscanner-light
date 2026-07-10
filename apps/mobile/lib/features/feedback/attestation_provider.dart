import 'dart:io';
import 'package:flutter/services.dart';

class Attestation {
  final String platform;
  final String token;
  final String challenge;
  final String? keyId;
  const Attestation({
    required this.platform,
    required this.token,
    required this.challenge,
    this.keyId,
  });

  Map<String, dynamic> toJson() => {
    'platform': platform,
    'token': token,
    'challenge': challenge,
    if (keyId != null) 'keyId': keyId,
  };
}

abstract class AttestationProvider {
  Future<Attestation?> attest(String challenge);
}

/// Production provider. Uses a platform channel to the native App Attest /
/// Play Integrity APIs. Returns null when the platform/OS cannot attest, so the
/// caller falls back to Turnstile. The native side is validated by the device test.
class PlatformAttestationProvider implements AttestationProvider {
  static const _channel = MethodChannel('camscanner/attestation');
  const PlatformAttestationProvider();

  @override
  Future<Attestation?> attest(String challenge) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('attest', {
        'challenge': challenge,
      });
      if (res == null || res['token'] == null) return null;
      return Attestation(
        platform: Platform.isIOS ? 'ios' : 'android',
        token: res['token'] as String,
        challenge: challenge,
        keyId: res['keyId'] as String?,
      );
    } on PlatformException {
      return null; // fall back to Turnstile
    }
  }
}

/// Host/test default: never attests, forcing the Turnstile path.
class NoAttestationProvider implements AttestationProvider {
  const NoAttestationProvider();
  @override
  Future<Attestation?> attest(String challenge) async => null;
}
