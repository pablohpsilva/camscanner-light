import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/gallery_picker.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_scan.dart';

void main() {
  test(
    'ScanDependencies default gallery picker is ImagePickerGalleryPicker',
    () {
      expect(
        const ScanDependencies().createGalleryPicker(),
        isA<ImagePickerGalleryPicker>(),
      );
    },
  );

  test('FakeGalleryPicker(cancel) returns null', () async {
    expect(await const FakeGalleryPicker(cancel: true).pick(), isNull);
  });

  test('FakeGalleryPicker(returnPath) returns that path', () async {
    final img = await const FakeGalleryPicker(
      returnPath: '/nonexistent/x.jpg',
    ).pick();
    expect(img, isNotNull);
    expect(img!.path, '/nonexistent/x.jpg');
  });

  test('FakeGalleryPicker(throwOnPick) throws', () async {
    expect(
      const FakeGalleryPicker(throwOnPick: true).pick(),
      throwsA(isA<Exception>()),
    );
  });
}
