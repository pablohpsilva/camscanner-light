import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_availability.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/library/home_screen.dart';

class _StubAvailability implements FeedbackAvailability {
  final bool v;
  const _StubAvailability(this.v);
  @override
  Future<bool> isAvailable() async => v;
}

void main() {
  testWidgets('overflow menu opens the feedback screen when worker is healthy',
      (t) async {
    await t.pumpWidget(MaterialApp(
      home: HomeScreen(
        feedbackDependencies: FeedbackDependencies(
          createAvailability: () => const _StubAvailability(true),
        ),
      ),
    ));
    // Let cold-start settle AND allow _probeFeedback to complete.
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-overflow-menu')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-menu-feedback')));
    await t.pumpAndSettle();
    expect(find.text('Send feedback'), findsOneWidget);
  });

  testWidgets('overflow menu is absent when worker is unhealthy', (t) async {
    await t.pumpWidget(MaterialApp(
      home: HomeScreen(
        feedbackDependencies: FeedbackDependencies(
          createAvailability: () => const _StubAvailability(false),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-overflow-menu')), findsNothing);
  });
}
