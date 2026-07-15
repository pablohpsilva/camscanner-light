import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

import '../../../support/localized_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  bool showFax = true,
  bool showShareLink = true,
}) async {
  await tester.pumpWidget(
    localizedTestApp(
      home: Scaffold(
        body: ShareMenuButton(
          buttonKey: const Key('smb'),
          onShare: () {},
          showFax: showFax,
          showShareLink: showShareLink,
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('smb')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default flags show both share-link and fax', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('share-menu-fax')), findsOneWidget);
    expect(find.byKey(const Key('share-menu-share-link')), findsOneWidget);
  });

  testWidgets('showFax: false hides the fax entry', (tester) async {
    await _pump(tester, showFax: false);
    expect(find.byKey(const Key('share-menu-fax')), findsNothing);
  });

  testWidgets('showShareLink: false hides the share-link entry', (
    tester,
  ) async {
    await _pump(tester, showShareLink: false);
    expect(find.byKey(const Key('share-menu-share-link')), findsNothing);
  });
}
