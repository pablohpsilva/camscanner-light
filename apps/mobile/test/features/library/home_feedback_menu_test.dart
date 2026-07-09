import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';

void main() {
  testWidgets('overflow menu opens the feedback screen', (t) async {
    await t.pumpWidget(const MaterialApp(home: HomeScreen()));
    await t.pump(const Duration(milliseconds: 200)); // let cold-start settle
    await t.tap(find.byKey(const Key('home-overflow-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-menu-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });
}
