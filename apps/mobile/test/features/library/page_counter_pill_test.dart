import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/page_counter_pill.dart';
import 'package:mobile/theme/ream_theme.dart';
import '../../support/ream_pump.dart';

void main() {
  group('PageCounterPill', () {
    testWidgets('displays current and total pages as "current / total"', (
      WidgetTester tester,
    ) async {
      await pumpReam(
        tester,
        const PageCounterPill(current: 2, total: 6),
        theme: ReamTheme.dark(),
      );

      expect(find.text('2 / 6'), findsOne);
    });
  });
}
