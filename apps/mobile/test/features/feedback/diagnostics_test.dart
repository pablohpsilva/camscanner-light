import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/diagnostics.dart';

void main() {
  test('toJson emits exactly the non-personal diagnostic fields', () {
    const d = Diagnostics(appVersion: '1.0.0', build: '42', os: 'iOS 18.3', device: 'iPhone15,2', locale: 'en_US');
    expect(d.toJson(), {
      'appVersion': '1.0.0', 'build': '42', 'os': 'iOS 18.3', 'device': 'iPhone15,2', 'locale': 'en_US',
    });
  });
}
