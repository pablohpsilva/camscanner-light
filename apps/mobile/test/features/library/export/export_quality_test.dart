import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';

void main() {
  test('preset values are exact', () {
    expect(ExportQuality.original.jpegQuality, isNull);
    expect(ExportQuality.original.maxDimension, isNull);
    expect(ExportQuality.original.reencodes, isFalse);

    expect(ExportQuality.high.jpegQuality, 85);
    expect(ExportQuality.high.maxDimension, isNull);
    expect(ExportQuality.high.reencodes, isTrue);

    expect(ExportQuality.medium.jpegQuality, 75);
    expect(ExportQuality.medium.maxDimension, 2200);

    expect(ExportQuality.low.jpegQuality, 60);
    expect(ExportQuality.low.maxDimension, 1600);
  });

  test('every preset has a label and description', () {
    for (final q in ExportQuality.values) {
      expect(q.label, isNotEmpty);
      expect(q.description, isNotEmpty);
    }
    expect(ExportQuality.medium.label, 'Medium');
    expect(ExportQuality.medium.description, 'Good for email');
  });
}
