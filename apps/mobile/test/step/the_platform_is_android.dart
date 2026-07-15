import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the platform is Android
Future<void> thePlatformIsAndroid(WidgetTester tester) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
}
