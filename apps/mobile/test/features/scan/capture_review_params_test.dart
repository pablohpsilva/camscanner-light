import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

void main() {
  testWidgets('renders custom title + acceptLabel and starts in initialMode', (
    tester,
  ) async {
    ImageEnhancer? accepted;
    await tester.pumpWidget(
      MaterialApp(
        home: CaptureReviewScreen(
          image: const CapturedImage('/nonexistent/front.jpg'),
          title: 'Front of ID',
          acceptLabel: 'Use',
          initialMode: EnhancerMode.none,
          enableCrop: true,
          onRetake: () {},
          onAccept: (_, enhancer) => accepted = enhancer,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Front of ID'), findsOneWidget);
    expect(find.text('Use'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump();
    expect(accepted, isA<NoneEnhancer>()); // initialMode none, untouched
  });
}
