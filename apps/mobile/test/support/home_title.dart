import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';

/// The home screen's "Documents" heading, in whatever locale the app resolved.
///
/// Steps must NOT hardcode the English string. The app follows the DEVICE
/// language, and device tests run on real hardware: this repo's iPhone is set
/// to Luxembourgish, where the heading reads "Dokumenter". Hardcoding
/// 'Documents' made e1_crop and e2_flatten fail on that phone only — a broken
/// assertion, not a broken app, and it looked like a real iOS defect for a
/// long time.
///
/// Reads the string from the live tree, so it stays correct in all 11 locales.
String homeTitle(WidgetTester tester) {
  final context = tester.element(find.byType(Scaffold).first);
  return context.l10n.homeDocumentsTitle;
}

/// Finder for the localized home heading.
Finder findHomeTitle(WidgetTester tester) => find.text(homeTitle(tester));
