import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';

void main() {
  test('default FeedbackDependencies expose a PrintAppLogger', () {
    const deps = FeedbackDependencies();
    expect(deps.logger(), isA<PrintAppLogger>());
  });

  test('an injected logger override is honored', () {
    final fake = SilentAppLogger();
    final deps = FeedbackDependencies(logger: () => fake);
    expect(deps.logger(), same(fake));
  });
}
