import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';

/// The running app's [AppLocalizations], read from the live widget tree.
///
/// Steps must resolve user-facing strings through this instead of hardcoding
/// English. The app follows the DEVICE language and device tests run on real
/// hardware — this repo's iPhone is set to Luxembourgish, so `find.text('Scan')`
/// and friends match nothing there and the failure looks like a broken app
/// rather than a broken assertion.
///
/// Two categories are deliberately NOT covered by this and keep their literals:
///   * scenarios that select a language first and then assert that exact
///     wording (the_home_title_is_shown_in_english / _spanish / …), and
///   * strings that are test data rather than UI (a document named 'Report').
AppLocalizations l10nOf(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  return context.l10n;
}
