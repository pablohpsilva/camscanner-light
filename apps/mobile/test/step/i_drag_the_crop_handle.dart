import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I drag the crop handle {'tr'}
///
/// [role] is one of the eight CropOverlay handles: the four corners
/// 'tl' / 'tr' / 'br' / 'bl', and the four edge midpoints
/// 'top' / 'right' / 'bottom' / 'left'. Each is keyed `crop-handle-<role>` and
/// routes to its own branch of CropOverlay's emitNew switch.
///
/// Only 'tl' was ever dragged (i_drag_the_top_left_crop_corner), so five of the
/// eight branches — the two right-hand corners and three of the edge midpoints —
/// had no test at all. The edge midpoints matter more than the corners: they
/// emit a DEVIATION from the edge centre (topMidDev and friends), which is what
/// bends an edge for a curved-page warp, not a simple quad move.
///
/// The drag is inward (towards the image centre) so the quad stays convex and
/// the handle stays on screen regardless of which side it started from.
Future<void> iDragTheCropHandle(WidgetTester tester, String role) async {
  const inward = {
    'tl': Offset(20, 20),
    'tr': Offset(-20, 20),
    'br': Offset(-20, -20),
    'bl': Offset(20, -20),
    'top': Offset(0, 20),
    'right': Offset(-20, 0),
    'bottom': Offset(0, -20),
    'left': Offset(20, 0),
  };
  final delta = inward[role];
  expect(
    delta,
    isNotNull,
    reason: "unknown crop handle '$role' — expected one of ${inward.keys}",
  );
  await tester.drag(find.byKey(Key('crop-handle-$role')), delta!);
  await tester.pumpAndSettle();
}
