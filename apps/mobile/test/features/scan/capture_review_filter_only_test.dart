import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

import '../../support/localized_app.dart';

Widget _host(Widget child) => localizedTestApp(home: child);

void main() {
  testWidgets('filter-only mode hides crop overlay and Reset', (tester) async {
    await tester.pumpWidget(
      _host(
        CaptureReviewScreen(
          image: const CapturedImage('/nonexistent/scan_1.jpg'),
          enableCrop: false,
          onRetake: () {},
          onAccept: (_, _) {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(CropOverlay), findsNothing);
    expect(find.byKey(const Key('crop-reset')), findsNothing);
    expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget);
  });

  testWidgets('filter-only accept returns full-frame corners + enhancer', (
    tester,
  ) async {
    CropCorners? corners;
    ImageEnhancer? enhancer;
    await tester.pumpWidget(
      _host(
        CaptureReviewScreen(
          image: const CapturedImage('/nonexistent/scan_1.jpg'),
          enableCrop: false,
          onRetake: () {},
          onAccept: (c, e) {
            corners = c;
            enhancer = e;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump();

    expect(corners, CropCorners.fullFrame);
    expect(enhancer, isA<AutoEnhancer>()); // default mode is auto
  });
}
