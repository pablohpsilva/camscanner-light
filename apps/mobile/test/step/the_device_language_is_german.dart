import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the device language is German
Future<void> theDeviceLanguageIsGerman(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = [const Locale('de')];
}
