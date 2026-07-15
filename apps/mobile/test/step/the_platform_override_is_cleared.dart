import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the platform override is cleared
///
/// Must be the LAST step of any scenario that set a platform override:
/// flutter_test asserts all foundation debug variables are unset at the end
/// of the testWidgets body, before tearDown/addTearDown ever run.
Future<void> thePlatformOverrideIsCleared(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = null;
}
