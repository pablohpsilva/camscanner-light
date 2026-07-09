import 'package:flutter_test/flutter_test.dart';
import '../../support/fake_scan.dart';

void main() {
  test(
    'FakePhotoCamera returns sequential shots then null; counts calls',
    () async {
      final cam = FakePhotoCamera(['/nonexistent/a.jpg', null]);
      final first = await cam.capture();
      final second = await cam.capture();
      final third = await cam.capture();
      expect(first?.path, '/nonexistent/a.jpg');
      expect(second, isNull); // explicit cancel entry
      expect(third, isNull); // exhausted
      expect(cam.captureCount, 3);
    },
  );
}
