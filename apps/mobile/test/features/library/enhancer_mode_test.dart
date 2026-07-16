import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';

void main() {
  group('EnhancerMode.fromIndex (P10 DUP-03)', () {
    test('maps each in-range index to its enum value', () {
      expect(EnhancerMode.fromIndex(0), EnhancerMode.none);
      expect(EnhancerMode.fromIndex(1), EnhancerMode.grayscale);
      expect(EnhancerMode.fromIndex(2), EnhancerMode.auto);
      expect(EnhancerMode.fromIndex(3), EnhancerMode.color);
    });

    test('falls back to none for a negative index', () {
      expect(EnhancerMode.fromIndex(-1), EnhancerMode.none);
    });

    test('falls back to none for an out-of-range index', () {
      expect(
        EnhancerMode.fromIndex(EnhancerMode.values.length),
        EnhancerMode.none,
      );
      expect(EnhancerMode.fromIndex(999), EnhancerMode.none);
    });
  });
}
