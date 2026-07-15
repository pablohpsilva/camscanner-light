import 'package:flutter_test/flutter_test.dart';

/// Usage: the device language override is cleared
///
/// Must be the LAST step of any scenario that set a device-locale override
/// via [localesTestValue]: flutter_test asserts test-only bindings are unset
/// at the end of the testWidgets body, before tearDown/addTearDown ever run.
Future<void> theDeviceLanguageOverrideIsCleared(WidgetTester tester) async {
  tester.platformDispatcher.clearLocalesTestValue();
}
