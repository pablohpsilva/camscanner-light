import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('share menu shows Fax → not available', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(documentId: 1, name: 'Scan X', repository: repo),
      ),
    );
    // Safe to settle: page image paths are NON-LOADABLE, which does not hang.
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-share-link')), findsOneWidget);
    await tester.tap(find.byKey(const Key('page-viewer-fax')));
    await tester.pumpAndSettle();
    expect(find.text(kFaxUnavailableMessage), findsOneWidget);
  });
}
