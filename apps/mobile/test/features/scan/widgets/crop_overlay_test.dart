import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

void main() {
  // 400x300 box; image 1000x750 (same 4:3 aspect) => contain rect fills the box
  // exactly: rect = (0,0) 400x300. So normalized (nx,ny) -> (nx*400, ny*300).
  Future<CropCorners?> pump(WidgetTester tester,
      {CropCorners corners = CropCorners.fullFrame, bool enabled = true}) async {
    CropCorners? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: corners,
              enabled: enabled,
              onCornersChanged: (c) => last = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return last;
  }

  testWidgets('renders the overlay and four handles by key', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
    for (final k in ['crop-handle-tl', 'crop-handle-tr', 'crop-handle-br', 'crop-handle-bl']) {
      expect(find.byKey(Key(k)), findsOneWidget);
    }
  });

  testWidgets('handles sit at the fitted-rect corners for full frame', (tester) async {
    await pump(tester);
    expect(tester.getCenter(find.byKey(const Key('crop-handle-tl'))),
        offsetMoreOrLessEquals(tester.getTopLeft(find.byKey(const Key('crop-overlay'))),
            epsilon: 1.0));
  });

  testWidgets('dragging top-left emits a clamped normalized corner', (tester) async {
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    // 40/400 = 0.1 ; 30/300 = 0.1
    expect(out, isNotNull);
    expect(out!.topLeft.dx, moreOrLessEquals(0.1, epsilon: 0.01));
    expect(out!.topLeft.dy, moreOrLessEquals(0.1, epsilon: 0.01));
  });

  testWidgets('dragging past the edge clamps to 0', (tester) async {
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(-80, -80));
    await tester.pumpAndSettle();
    expect(out!.topLeft, const Offset(0, 0));
  });

  testWidgets('empty imageSize renders no handles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400, height: 300,
          child: CropOverlay(
            imageSize: Size.zero,
            image: ColoredBox(color: Colors.black),
            corners: CropCorners.fullFrame,
            onCornersChanged: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-handle-tl')), findsNothing);
  });

  testWidgets('disabled overlay ignores drags', (tester) async {
    // NOTE: capture the callback ACROSS the drag (do not use pump()'s return,
    // which snapshots before the drag and would make this assertion vacuous).
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              enabled: false,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(out, isNull); // disabled => onCornersChanged never fired during the drag
  });

  testWidgets('handles carry semantic labels', (tester) async {
    await pump(tester);
    expect(find.bySemanticsLabel('Top-left crop corner'), findsOneWidget);
    expect(find.bySemanticsLabel('Bottom-right crop corner'), findsOneWidget);
  });

  testWidgets('default highlightColor is Colors.blue', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 600,
        child: CropOverlay(
          imageSize: const Size(400, 600),
          image: const ColoredBox(color: Colors.grey),
          corners: CropCorners.fullFrame,
          onCornersChanged: (_) {},
        ),
      ),
    ));
    expect(
      tester.widget<CropOverlay>(find.byType(CropOverlay)).highlightColor,
      Colors.blue,
    );
  });

  testWidgets('highlightColor Colors.green propagates to handle border',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 600,
        child: CropOverlay(
          imageSize: const Size(400, 600),
          image: const ColoredBox(color: Colors.grey),
          corners: CropCorners.fullFrame,
          onCornersChanged: (_) {},
          highlightColor: Colors.green,
        ),
      ),
    ));
    // _DragHandle renders: GestureDetector > Container(44×44) > Container(18×18, decoration)
    // The inner Container has the BoxDecoration with the border.
    final handle = find.byKey(const Key('crop-handle-tl'));
    final decoratedContainer = find.descendant(
      of: handle,
      matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration),
    );
    final container = tester.widget<Container>(decoratedContainer);
    final deco = container.decoration! as BoxDecoration;
    expect(deco.border, Border.all(color: Colors.green, width: 2));
  });

  testWidgets('highlightColor Colors.green propagates to quad painter',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 400,
        height: 600,
        child: CropOverlay(
          imageSize: const Size(400, 600),
          image: const ColoredBox(color: Colors.grey),
          corners: CropCorners.fullFrame,
          onCornersChanged: (_) {},
          highlightColor: Colors.green,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    // _QuadPainter is private; access its fields via a dynamic cast on the
    // last CustomPaint in the overlay subtree (the quad outline painter).
    final paint = tester.widget<CustomPaint>(find.byType(CustomPaint).last);
    // ignore: avoid_dynamic_calls
    expect((paint.painter! as dynamic).highlightColor, Colors.green);
  });
}

void _noop(CropCorners _) {}
