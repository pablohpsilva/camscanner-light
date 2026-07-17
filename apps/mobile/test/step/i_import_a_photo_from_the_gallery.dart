import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I import a photo from the gallery
///
/// Taps the Home app-bar import button (key `home-import`, Task 8.1). The launch
/// step's library deps (tempLibraryDependencies) wire a FakeGalleryPicker that
/// returns a real temp file (P14 task 4), so this routes into the crop+filter
/// review screen.
Future<void> iImportAPhotoFromTheGallery(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-import')));
  await tester.pumpAndSettle();
}
