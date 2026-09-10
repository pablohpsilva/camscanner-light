// apps/mobile/integration_test/fb2_diagnostics_device_test.dart
//
// PlatformDiagnosticsCollector can only run on a device: it goes through
// package_info_plus and device_info_plus, both native. Every feedback test —
// host and device — injects FakeDiagnosticsCollector, so the real collector had
// never executed anywhere, and its two platform branches (iOS / Android) were
// uncovered by both suites.
//
// This also checks the privacy guarantee in the class doc — "NEVER contains
// document content or file paths" — which nothing verified. That claim is the
// reason this payload can be attached to a public GitHub issue, so it is worth
// a test rather than a comment.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/feedback/diagnostics.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the real collector fills every field on this platform', (
    tester,
  ) async {
    final d = await const PlatformDiagnosticsCollector().collect();

    expect(d.appVersion, isNotEmpty, reason: 'appVersion from package_info');
    expect(d.build, isNotEmpty, reason: 'build number from package_info');
    expect(d.locale, isNotEmpty, reason: 'locale from PlatformDispatcher');

    // 'unknown' is the untouched default — seeing it means the platform branch
    // did not run, which is exactly the bug this test exists to catch.
    expect(d.os, isNot('unknown'));
    expect(d.device, isNot('unknown'));

    if (Platform.isIOS) {
      expect(d.os, startsWith('iOS '));
      // utsname.machine, e.g. iPhone15,2 — a model id, never a serial.
      expect(d.device, isNotEmpty);
    } else if (Platform.isAndroid) {
      expect(d.os, startsWith('Android '));
      expect(d.device, contains(' '), reason: 'manufacturer + model');
    }

    // ignore: avoid_print
    print(
      'DIAGNOSTICS os="${d.os}" device="${d.device}" '
      'v${d.appVersion}+${d.build} locale=${d.locale}',
    );
  });

  testWidgets('diagnostics carry no file paths or document content', (
    tester,
  ) async {
    final d = await const PlatformDiagnosticsCollector().collect();
    final serialized = d.toJson().values.join(' ');

    // A path separator, a container GUID or a documents dir leaking in here
    // would be published verbatim on a GitHub issue.
    expect(serialized, isNot(contains('/')), reason: 'no filesystem paths');
    expect(serialized.toLowerCase(), isNot(contains('documents')));
    expect(serialized.toLowerCase(), isNot(contains('.jpg')));
    expect(serialized.toLowerCase(), isNot(contains('.sqlite')));

    // toJson must expose exactly the five declared keys — nothing added later
    // gets published without someone updating this list.
    expect(d.toJson().keys.toSet(), {
      'appVersion',
      'build',
      'os',
      'device',
      'locale',
    });
  });
}
