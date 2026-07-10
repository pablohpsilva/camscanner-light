import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/widgets/confidence_chip.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('high confidence renders label + green dot', (tester) async {
    await pumpReam(
      tester,
      const ConfidenceChip(
        level: ConfidenceLevel.high,
        label: 'High confidence',
      ),
    );
    expect(find.text('High confidence'), findsOneWidget);
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const Key('confidence-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, ReamColors.light.green);
  });

  testWidgets('verify level uses amber', (tester) async {
    await pumpReam(
      tester,
      const ConfidenceChip(
        level: ConfidenceLevel.verify,
        label: 'Please verify',
      ),
    );
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const Key('confidence-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, ReamColors.light.amber);
  });
}
