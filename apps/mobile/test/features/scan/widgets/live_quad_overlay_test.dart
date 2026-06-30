import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders with Key(live-quad-overlay)', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });

  testWidgets('contains a CustomPaint', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    // Scope to the overlay subtree — Scaffold/Material may also render CustomPaint.
    expect(
      find.descendant(
        of: find.byKey(const Key('live-quad-overlay')),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
  });

  testWidgets('fills its parent container', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: const Size(1920, 1080),
        color: Colors.green,
      ),
    )));
    final size =
        tester.getSize(find.byKey(const Key('live-quad-overlay')));
    expect(size, const Size(400, 300));
  });

  testWidgets('handles zero previewSize gracefully', (tester) async {
    await tester.pumpWidget(host(SizedBox(
      width: 400,
      height: 300,
      child: LiveQuadOverlay(
        corners: CropCorners.fullFrame,
        previewSize: Size.zero,
        color: Colors.green,
      ),
    )));
    // Should not throw — falls back to empty box
    expect(find.byKey(const Key('live-quad-overlay')), findsOneWidget);
  });
}
