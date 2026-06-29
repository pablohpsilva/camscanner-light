import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the sort chip for [criterion] is selected (active).
Future<void> iSeeTheSortChipIsActive(
    WidgetTester tester, String criterion) async {
  final chip =
      tester.widget<ChoiceChip>(find.byKey(Key('sort-chip-$criterion')));
  expect(chip.selected, isTrue);
}
