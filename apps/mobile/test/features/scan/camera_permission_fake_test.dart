import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_scan.dart';

void main() {
  test(
    'FakeCameraPermission returns configured value and counts calls',
    () async {
      final denied = FakeCameraPermission(granted: false);
      expect(await denied.ensure(), isFalse);
      expect(denied.calls, 1);
      final granted = FakeCameraPermission();
      expect(await granted.ensure(), isTrue);
    },
  );
}
