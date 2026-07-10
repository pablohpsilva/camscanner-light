import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I drag the top left crop corner
Future<void> iDragTheTopLeftCropCorner(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const Key('crop-handle-tl')),
    const Offset(20, 20),
  );
  await tester.pumpAndSettle();
}
