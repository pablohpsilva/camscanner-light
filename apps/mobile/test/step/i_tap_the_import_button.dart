import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the import button
///
/// Taps the Home app-bar import button (key `home-import`, added in Task 8.1),
/// which picks via the injected gallery picker and opens the crop+filter review
/// screen. The launch step's `grantedScanDependencies()` wires a
/// `FakeGalleryPicker` returning a real temp file.
Future<void> iTapTheImportButton(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-import')));
  await tester.pumpAndSettle();
}
