import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';
import 'package:mobile/theme/ream_colors.dart';

import '../../support/localized_app.dart';

void main() {
  testWidgets('crop editor uses dark Ream chrome + keeps Accept', (
    tester,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: EditCropScreen(
          imagePath: '/nonexistent.jpg',
          initialCorners: const CropCorners(
            topLeft: Offset(0, 0),
            topRight: Offset(1, 0),
            bottomRight: Offset(1, 1),
            bottomLeft: Offset(0, 1),
          ),
          decodeImageSize: (_) async => const Size(100, 200),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('edit-crop-accept')), findsOneWidget);
    // Body background is the dark Ream paper tone, not raw Colors.black.
    final box = tester.widget<ColoredBox>(
      find
          .descendant(
            of: find.byType(Scaffold),
            matching: find.byType(ColoredBox),
          )
          .last,
    );
    expect(box.color, ReamColors.dark.paper);
  });
}
