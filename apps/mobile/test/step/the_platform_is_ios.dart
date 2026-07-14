import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the platform is iOS
///
/// NOTE: no addTearDown here — flutter_test's foundation-variable invariant
/// runs before tearDown callbacks, so each scenario must end with the
/// "the platform override is cleared" step instead.
Future<void> thePlatformIsIos(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
}
