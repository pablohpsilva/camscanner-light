import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_l10n.dart';

/// Asserts the App sort pill's active criterion is [criterion]
/// ('name', 'created', 'modified') by checking its displayed label.
///
/// The label is resolved through the running app's [AppLocalizations] rather
/// than hardcoded, because the sort pill renders `context.l10n.sortName` and
/// friends. The app follows the DEVICE language, and this repo's test iPhone is
/// set to Luxembourgish — a hardcoded 'Name' matches nothing there and the
/// failure reads like a broken sort feature instead of a broken assertion.
Future<void> iSeeTheSortChipIsActive(
  WidgetTester tester,
  String criterion,
) async {
  final l10n = l10nOf(tester);
  final labels = {
    'name': l10n.sortName,
    'created': l10n.sortCreated,
    'modified': l10n.sortModified,
  };
  final label = labels[criterion] ?? criterion;
  expect(
    find.descendant(
      of: find.byKey(const Key('sort-pill')),
      matching: find.text(label),
    ),
    findsOneWidget,
  );
}
