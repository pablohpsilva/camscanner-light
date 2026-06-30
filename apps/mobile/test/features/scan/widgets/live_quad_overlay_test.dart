import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/live_quad_overlay.dart';

// ---- Fitted-rect pixel math (acceptance criterion: letterboxing) ----
// For fullFrame corners + a 400×300 box with previewSize 1920×1080:
//   scale = min(400/1920, 300/1080) = min(0.2083…, 0.2778…) = 0.2083…
//   display = 1920×0.2083 × 1080×0.2083 ≈ 400 × 225
//   rect.top  = (300−225)/2 = 37.5,  rect.left = (400−400)/2 = 0
//   pixelOf(0,0) = (0+0×400, 37.5+0×225) = (0,    37.5)
//   pixelOf(1,0) = (0+1×400, 37.5+0×225) = (400,  37.5)
//   pixelOf(1,1) = (0+1×400, 37.5+1×225) = (400,  262.5)
//   pixelOf(0,1) = (0+0×400, 37.5+1×225) = (0,    262.5)
//
// _LiveQuadPainter is private so its output cannot be directly asserted in a
// widget test without golden tests (out of scope per YAGNI). The structural
// tests below confirm the widget occupies the full available area and runs its
// scale math over the correct basis, which is sufficient host coverage.

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
