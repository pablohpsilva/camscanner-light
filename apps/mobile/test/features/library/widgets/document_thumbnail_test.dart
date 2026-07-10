import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/document_thumbnail.dart';

void main() {
  Future<void> pump(WidgetTester tester, String? path) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: DocumentThumbnail(path: path)),
    ),
  );

  testWidgets('null path renders the placeholder icon and no Image', (
    tester,
  ) async {
    await pump(tester, null);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  // IMPORTANT (verified by spike): on host, Image.file's real dart:io read does
  // NOT complete inside flutter_test's FakeAsync zone, so errorBuilder never
  // fires here — asserting the rendered placeholder for a non-null path is
  // UNRELIABLE. Image.file also does NOT hang (a non-loadable path settles).
  // So we assert the WIRING deterministically (downsampled provider +
  // errorBuilder); the missing-file→placeholder *rendering* is a Flutter
  // contract, verified on-device (REAL_DEVICE lane). cacheWidth wraps the
  // FileImage in a ResizeImage.
  testWidgets('a non-null path builds a downsampled Image with errorBuilder', (
    tester,
  ) async {
    await pump(tester, '/nonexistent/missing-thumb.jpg');
    await tester.pump(); // single pump; no settle (and none needed)
    final img = tester.widget<Image>(find.byType(Image));
    expect(img.errorBuilder, isNotNull);
    expect(img.image, isA<ResizeImage>());
  });
}
