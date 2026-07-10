import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_availability.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

class _StubAvailability implements FeedbackAvailability {
  final bool v;
  const _StubAvailability(this.v);
  @override
  Future<bool> isAvailable() async => v;
}

void main() {
  testWidgets(
    'settings gear opens the feedback screen when worker is healthy',
    (t) async {
      await t.pumpWidget(
        MaterialApp(
          theme: ReamTheme.light(),
          home: HomeScreen(
            feedbackDependencies: FeedbackDependencies(
              createAvailability: () => const _StubAvailability(true),
            ),
          ),
        ),
      );
      // Let cold-start settle AND allow _probeFeedback to complete.
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-settings')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-menu-feedback')));
      await t.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
    },
  );

  testWidgets('feedback item is absent from the gear menu when unhealthy', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          feedbackDependencies: FeedbackDependencies(
            createAvailability: () => const _StubAvailability(false),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('home-menu-feedback')), findsNothing);
  });
}
