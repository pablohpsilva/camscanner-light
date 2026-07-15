import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/library_dependencies.dart';

void main() {
  test('default LibraryDependencies expose a PrintAppLogger', () {
    const deps = LibraryDependencies();
    expect(deps.logger(), isA<PrintAppLogger>());
  });

  test('an injected logger override is honored', () {
    final fake = SilentAppLogger();
    final deps = LibraryDependencies(logger: () => fake);
    expect(deps.logger(), same(fake));
  });
}
