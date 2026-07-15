import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the app is laid out right-to-left
Future<void> theAppIsLaidOutRighttoleft(WidgetTester tester) async {
  final context = tester.element(find.byType(Scaffold).first);
  expect(Directionality.of(context), TextDirection.rtl);
}
