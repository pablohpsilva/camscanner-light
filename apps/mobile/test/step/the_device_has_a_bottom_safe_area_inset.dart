import 'package:flutter_test/flutter_test.dart';

/// The simulated home-indicator inset, in logical pixels (iPhone gesture bar).
const double kFakeBottomInset = 34;

/// Usage: the device has a bottom safe area inset
///
/// Simulates an iPhone-style home-indicator inset. Must run BEFORE the app is
/// pumped so MediaQuery picks it up. FakeViewPadding is physical pixels.
Future<void> theDeviceHasABottomSafeAreaInset(WidgetTester tester) async {
  tester.view.padding = FakeViewPadding(
    bottom: kFakeBottomInset * tester.view.devicePixelRatio,
  );
  addTearDown(tester.view.resetPadding);
}
