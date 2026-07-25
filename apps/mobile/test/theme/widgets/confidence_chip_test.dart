import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_colors.dart';
import 'package:mobile/theme/widgets/confidence_chip.dart';
import '../../support/app_pump.dart';

void main() {
  testWidgets('high confidence renders label + green dot', (tester) async {
    await pumpApp(
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
    expect((dot.decoration as BoxDecoration).color, AppColors.light.green);
  });

  testWidgets('verify level uses amber', (tester) async {
    await pumpApp(
      tester,
      const ConfidenceChip(
        level: ConfidenceLevel.verify,
        label: 'Please verify',
      ),
    );
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const Key('confidence-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, AppColors.light.amber);
  });

  testWidgets('info level renders label + blue dot', (tester) async {
    await pumpApp(
      tester,
      const ConfidenceChip(level: ConfidenceLevel.info, label: 'Info'),
    );
    expect(find.text('Info'), findsOneWidget);
    final dot = tester.widget<DecoratedBox>(
      find.byKey(const Key('confidence-dot')),
    );
    expect((dot.decoration as BoxDecoration).color, AppColors.light.blue);
  });
}
