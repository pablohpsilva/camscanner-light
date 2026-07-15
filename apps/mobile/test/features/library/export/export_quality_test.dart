import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/l10n/l10n.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

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
      expect(q.label(l10n), isNotEmpty);
      expect(q.description(l10n), isNotEmpty);
    }
    expect(ExportQuality.medium.label(l10n), 'Medium');
    expect(ExportQuality.medium.description(l10n), 'Good for email');
  });
}
