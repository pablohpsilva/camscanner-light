import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/diagnostics.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PackageInfo.setMockInitialValues(
      appName: 'x',
      packageName: 'y',
      version: '1.2.3',
      buildNumber: '42',
      buildSignature: '',
      installerStore: null,
    );
  });

  test('collect() reads app version/build from PackageInfo; '
      'os/device are unknown on a non-iOS/Android host', () async {
    final diagnostics = await const PlatformDiagnosticsCollector().collect();

    expect(diagnostics.appVersion, '1.2.3');
    expect(diagnostics.build, '42');
    expect(diagnostics.os, 'unknown');
    expect(diagnostics.device, 'unknown');
  });

  test('toJson emits exactly the non-personal diagnostic fields', () {
    const d = Diagnostics(
      appVersion: 'a',
      build: 'b',
      os: 'c',
      device: 'd',
      locale: 'e',
    );
    expect(d.toJson(), {
      'appVersion': 'a',
      'build': 'b',
      'os': 'c',
      'device': 'd',
      'locale': 'e',
    });
  });
}
