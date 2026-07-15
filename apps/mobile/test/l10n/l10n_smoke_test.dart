import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/l10n/l10n.dart';

import '../support/localized_app.dart';

void main() {
  testWidgets('context.l10n resolves English strings', (tester) async {
    late String title;
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) {
            title = context.l10n.homeDocumentsTitle;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(title, 'Documents');
  });
}
