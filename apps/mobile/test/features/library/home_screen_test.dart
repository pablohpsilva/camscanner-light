import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
  }

  testWidgets('shows the Documents app bar title', (tester) async {
    await pumpHome(tester);
    expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no documents',
      (tester) async {
    await pumpHome(tester);
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('shows a tappable Scan button', (tester) async {
    await pumpHome(tester);
    final scan = find.widgetWithText(FloatingActionButton, 'Scan');
    expect(scan, findsOneWidget);
    await tester.tap(scan); // no-op for now, must not throw
    await tester.pump();
  });

  testWidgets('tapping Scan opens the camera screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(dependencies: grantedScanDependencies())),
    );

    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });
}
