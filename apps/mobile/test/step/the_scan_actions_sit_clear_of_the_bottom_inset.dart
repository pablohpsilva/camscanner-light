import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'the_device_has_a_bottom_safe_area_inset.dart';

/// Usage: the scan actions sit clear of the bottom inset
///
/// With no donation banner below them (iOS), the Scan / ID card / Import row
/// must clear the home-indicator inset with a visible gap on top of it —
/// otherwise the buttons sit in the gesture area and can't be tapped reliably.
Future<void> theScanActionsSitClearOfTheBottomInset(WidgetTester tester) async {
  final screenHeight =
      tester.view.physicalSize.height / tester.view.devicePixelRatio;
  for (final key in const ['home-scan', 'home-scan-id', 'home-import']) {
    final bottom = tester.getBottomLeft(find.byKey(Key(key))).dy;
    expect(
      screenHeight - bottom,
      greaterThanOrEqualTo(kFakeBottomInset + 8),
      reason: '$key must sit at least 8px above the home-indicator inset',
    );
  }
}
