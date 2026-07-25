import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/widgets/app_back_header.dart';

void main() {
  testWidgets('shows title, default back key, fires onBack', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBackHeader(
            title: 'Export as PDF',
            onBack: () => popped = true,
          ),
        ),
      ),
    );
    expect(find.text('Export as PDF'), findsOneWidget);
    expect(find.byKey(const Key('back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('back')));
    expect(popped, isTrue);
  });

  testWidgets('honours a custom backKey', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          appBar: AppBackHeader(
            title: 'X',
            backKey: const Key('recognized-text-back'),
            onBack: () {},
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('recognized-text-back')), findsOneWidget);
  });
}
