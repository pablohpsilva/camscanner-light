import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  testWidgets('Protect with password exports a protected PDF', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 5, name: 'Doc', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-protect')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('password-field')), 'secret');
    await tester.pump();
    await tester.tap(find.byKey(const Key('password-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.lastProtectPassword, 'secret');
    expect(find.text('Protected PDF ready'), findsOneWidget);
  });
}
