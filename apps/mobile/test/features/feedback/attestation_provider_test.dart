import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/attestation_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('camscanner/attestation');
  final messenger = TestWidgetsFlutterBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test(
    'attest() returns an Attestation built from a successful channel result',
    () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        expect(call.method, 'attest');
        expect(call.arguments, {'challenge': 'chal'});
        return {'token': 'tok', 'keyId': 'kid'};
      });

      final result = await const PlatformAttestationProvider().attest('chal');

      expect(result, isNotNull);
      expect(result!.token, 'tok');
      expect(result.keyId, 'kid');
      expect(result.challenge, 'chal');
      expect(result.platform, anyOf('ios', 'android'));
      expect(result.platform, Platform.isIOS ? 'ios' : 'android');
    },
  );

  test('attest() returns null when the channel result is null', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return null;
    });

    final result = await const PlatformAttestationProvider().attest('chal');

    expect(result, isNull);
  });

  test('attest() returns null when the result has no token', () async {
    messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
      return {'foo': 'bar'};
    });

    final result = await const PlatformAttestationProvider().attest('chal');

    expect(result, isNull);
  });

  test(
    'attest() returns null when the channel throws a PlatformException',
    () async {
      messenger.setMockMethodCallHandler(channel, (MethodCall call) async {
        throw PlatformException(code: 'x');
      });

      final result = await const PlatformAttestationProvider().attest('chal');

      expect(result, isNull);
    },
  );

  test('NoAttestationProvider.attest() always returns null', () async {
    final result = await const NoAttestationProvider().attest('c');

    expect(result, isNull);
  });

  test('Attestation.toJson() includes keyId only when non-null', () {
    const withKeyId = Attestation(
      platform: 'ios',
      token: 't',
      challenge: 'c',
      keyId: 'k',
    );
    expect(withKeyId.toJson(), {
      'platform': 'ios',
      'token': 't',
      'challenge': 'c',
      'keyId': 'k',
    });

    const withoutKeyId = Attestation(
      platform: 'ios',
      token: 't',
      challenge: 'c',
    );
    final json = withoutKeyId.toJson();
    expect(json.containsKey('keyId'), isFalse);
    expect(json, {'platform': 'ios', 'token': 't', 'challenge': 'c'});
  });
}
