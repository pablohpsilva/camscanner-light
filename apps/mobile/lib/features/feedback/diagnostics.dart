import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Non-personal diagnostics. NEVER contains document content or file paths.
class Diagnostics {
  final String appVersion, build, os, device, locale;
  const Diagnostics({
    required this.appVersion,
    required this.build,
    required this.os,
    required this.device,
    required this.locale,
  });

  Map<String, dynamic> toJson() => {
        'appVersion': appVersion,
        'build': build,
        'os': os,
        'device': device,
        'locale': locale,
      };
}

abstract class DiagnosticsCollector {
  Future<Diagnostics> collect();
}

class PlatformDiagnosticsCollector implements DiagnosticsCollector {
  const PlatformDiagnosticsCollector();

  @override
  Future<Diagnostics> collect() async {
    final pkg = await PackageInfo.fromPlatform();
    final info = DeviceInfoPlugin();
    String os = 'unknown', device = 'unknown';
    if (Platform.isIOS) {
      final ios = await info.iosInfo;
      os = 'iOS ${ios.systemVersion}';
      device = ios.utsname.machine; // e.g. iPhone15,2 — model id, not a serial
    } else if (Platform.isAndroid) {
      final a = await info.androidInfo;
      os = 'Android ${a.version.release}';
      device = '${a.manufacturer} ${a.model}';
    }
    return Diagnostics(
      appVersion: pkg.version,
      build: pkg.buildNumber,
      os: os,
      device: device,
      locale: ui.PlatformDispatcher.instance.locale.toString(),
    );
  }
}
