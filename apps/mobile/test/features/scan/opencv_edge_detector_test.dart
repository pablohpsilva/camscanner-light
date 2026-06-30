import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/library/crop_corners.dart';

void main() {
  group('DetectionResult', () {
    final corners = CropCorners(
      topLeft: const Offset(0.1, 0.1),
      topRight: const Offset(0.9, 0.1),
      bottomRight: const Offset(0.9, 0.9),
      bottomLeft: const Offset(0.1, 0.9),
    );
    final result = DetectionResult(corners: corners, confidence: 0.8);

    test('equality: same corners and confidence', () {
      final other = DetectionResult(corners: corners, confidence: 0.8);
      expect(result, equals(other));
    });

    test('equality: different confidence', () {
      final other = DetectionResult(corners: corners, confidence: 0.5);
      expect(result, isNot(equals(other)));
    });

    test('equality: different corners', () {
      final other = DetectionResult(
        corners: CropCorners(
          topLeft: const Offset(0.2, 0.2),
          topRight: const Offset(0.8, 0.2),
          bottomRight: const Offset(0.8, 0.8),
          bottomLeft: const Offset(0.2, 0.8),
        ),
        confidence: 0.8,
      );
      expect(result, isNot(equals(other)));
    });

    test('hashCode matches equal instances', () {
      final other = DetectionResult(corners: corners, confidence: 0.8);
      expect(result.hashCode, equals(other.hashCode));
    });

    test('toString contains corners and confidence', () {
      expect(result.toString(), contains('DetectionResult'));
      expect(result.toString(), contains('confidence'));
    });
  });
}
