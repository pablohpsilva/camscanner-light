import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the device language is Brazilian Portuguese
Future<void> theDeviceLanguageIsBrazilianPortuguese(WidgetTester tester) async {
  tester.platformDispatcher.localesTestValue = [const Locale('pt', 'BR')];
}
