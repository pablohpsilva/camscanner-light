import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/features/library/widgets/editor_top_bar.dart';

void main() {
  Future<void> pumpBar(
    WidgetTester tester, {
    String title = 'Lease Agreement',
    VoidCallback? onBack,
    Widget? trailing,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.dark(),
        home: Scaffold(
          appBar: EditorTopBar(
            title: title,
            onBack: onBack,
            trailing: trailing,
          ),
          body: const SizedBox(),
        ),
      ),
    );
  }

  testWidgets('title text is rendered', (tester) async {
    await pumpBar(tester);
    expect(find.text('Lease Agreement'), findsOneWidget);
  });

  testWidgets('back button is present and tapping fires onBack', (
    tester,
  ) async {
    var backs = 0;
    await pumpBar(tester, onBack: () => backs++);
    expect(find.byKey(const Key('page-viewer-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-viewer-back')));
    expect(backs, 1);
  });

  testWidgets('trailing widget renders when provided', (tester) async {
    await pumpBar(
      tester,
      trailing: const Icon(Icons.more_horiz, key: Key('ovf')),
    );
    expect(find.byKey(const Key('ovf')), findsOneWidget);
  });

  testWidgets('no trailing widget renders spacer and back+title still show', (
    tester,
  ) async {
    await pumpBar(tester, onBack: () {});
    expect(find.text('Lease Agreement'), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-back')), findsOneWidget);
  });
}
