import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  testWidgets('crop passes the page rotation into the editor', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/a.jpg', rotationQuarterTurns: 1),
      ],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-edit')));
    await tester.pumpAndSettle();

    final editor = tester.widget<EditCropScreen>(find.byType(EditCropScreen));
    expect(editor.quarterTurns, 1);
  });
}
