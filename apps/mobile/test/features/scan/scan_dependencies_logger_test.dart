import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

void main() {
  test('default ScanDependencies expose a PrintAppLogger', () {
    const deps = ScanDependencies();
    expect(deps.logger(), isA<PrintAppLogger>());
  });

  test('an injected logger override is honored', () {
    final fake = SilentAppLogger();
    final deps = ScanDependencies(logger: () => fake);
    expect(deps.logger(), same(fake));
  });
}
