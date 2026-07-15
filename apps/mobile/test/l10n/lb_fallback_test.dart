import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';
import 'package:mobile/l10n/lb_fallback_delegates.dart';

void main() {
  testWidgets('MaterialApp pumps with locale lb without throwing', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('lb'),
        supportedLocales: const [Locale('lb')],
        localizationsDelegates: const [
          ...kLbFallbackDelegates,
          ...AppLocalizations.localizationsDelegates,
        ],
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: Text('hello'));
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Framework strings resolve (German fallback under the hood).
    expect(MaterialLocalizations.of(ctx).cancelButtonLabel, isNotEmpty);
    expect(Directionality.of(ctx), TextDirection.ltr);
  });
}
