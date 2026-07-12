import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';

void main() {
  testWidgets('odd quarterTurns wraps the image in a RotatedBox', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditCropScreen(
          imagePath: '/nonexistent.jpg',
          initialCorners: CropCorners.fullFrame,
          quarterTurns: 1,
          decodeImageSize: (_) async => const Size(60, 40),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rotated = tester.widgetList<RotatedBox>(find.byType(RotatedBox));
    expect(
      rotated.any((r) => r.quarterTurns % 4 == 1),
      isTrue,
      reason: 'the crop image must be rotated to the display orientation',
    );
  });
}
