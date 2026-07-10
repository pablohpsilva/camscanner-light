import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the Ream sort pill's active criterion is [criterion]
/// ('name', 'created', 'modified') by checking its displayed label.
Future<void> iSeeTheSortChipIsActive(
  WidgetTester tester,
  String criterion,
) async {
  const labels = {'name': 'Name', 'created': 'Created', 'modified': 'Modified'};
  final label = labels[criterion] ?? criterion;
  expect(
    find.descendant(
      of: find.byKey(const Key('sort-pill')),
      matching: find.text(label),
    ),
    findsOneWidget,
  );
}
