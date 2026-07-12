import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_back_header.dart';

void main() {
  testWidgets('shows title, default back key, fires onBack', (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: Scaffold(
          appBar: ReamBackHeader(
            title: 'Export as PDF',
            onBack: () => popped = true,
          ),
        ),
      ),
    );
    expect(find.text('Export as PDF'), findsOneWidget);
    expect(find.byKey(const Key('ream-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ream-back')));
    expect(popped, isTrue);
  });

  testWidgets('honours a custom backKey', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: Scaffold(
          appBar: ReamBackHeader(
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
