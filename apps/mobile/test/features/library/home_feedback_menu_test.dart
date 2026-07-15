import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/feedback/feedback_availability.dart';
import 'package:mobile/features/feedback/feedback_dependencies.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/localized_app.dart';

class _StubAvailability implements FeedbackAvailability {
  final bool v;
  const _StubAvailability(this.v);
  @override
  Future<bool> isAvailable() async => v;
}

Widget _host(bool healthy) => localizedTestApp(
  home: HomeScreen(
    feedbackDependencies: FeedbackDependencies(
      createAvailability: () => _StubAvailability(healthy),
    ),
  ),
);

void main() {
  testWidgets(
    'settings gear opens settings, and feedback from there when healthy',
    (t) async {
      await t.pumpWidget(_host(true));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('home-settings')));
      await t.pumpAndSettle();
      expect(find.text('Settings'), findsOneWidget);
      await t.tap(find.byKey(const Key('settings-feedback')));
      await t.pumpAndSettle();
      expect(find.text('Send feedback'), findsOneWidget);
    },
  );

  testWidgets('feedback row is absent in settings when unhealthy', (t) async {
    await t.pumpWidget(_host(false));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('home-settings')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('settings-feedback')), findsNothing);
  });
}
