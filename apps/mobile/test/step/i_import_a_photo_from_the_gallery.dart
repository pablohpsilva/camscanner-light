import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I import a photo from the gallery
///
/// Taps the camera screen's import button. The launch step's
/// grantedScanDependencies wires a FakeGalleryPicker that returns a real temp
/// file, so this routes into the review screen exactly like a capture.
Future<void> iImportAPhotoFromTheGallery(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('camera-import')));
  await tester.pumpAndSettle();
}
