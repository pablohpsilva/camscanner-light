import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the scan button is on the left
///
/// Asserts the primary Scan CTA sits physically left of the secondary
/// icon-only actions (ID card, Import).
Future<void> theScanButtonIsOnTheLeft(WidgetTester tester) async {
  final scan = tester.getCenter(find.byKey(const Key('home-scan'))).dx;
  final id = tester.getCenter(find.byKey(const Key('home-scan-id'))).dx;
  final import = tester.getCenter(find.byKey(const Key('home-import'))).dx;
  expect(scan, lessThan(id));
  expect(scan, lessThan(import));
}
