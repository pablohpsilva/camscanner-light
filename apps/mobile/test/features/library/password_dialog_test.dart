import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/password_dialog.dart';

import '../../support/localized_app.dart';

void main() {
  testWidgets('returns the entered password on Protect', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    result = await showPasswordDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Protect is disabled until text is entered.
    final btn = tester.widget<TextButton>(
      find.byKey(const Key('password-confirm')),
    );
    expect(btn.onPressed, isNull);

    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-confirm')));
    await tester.pumpAndSettle();

    expect(result, 'secret');
  });

  testWidgets('returns null on Cancel', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async =>
                    result = await showPasswordDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('password-cancel')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
