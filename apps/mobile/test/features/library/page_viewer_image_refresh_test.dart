import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  testWidgets(
    'page image re-decodes after an edit (key epoch bumps for a same-path flat)',
    (tester) async {
      // A page whose display is a flat derivative at a FIXED path — the case
      // where a regenerated flat reuses its path and FileImage would otherwise
      // show a stale, already-decoded frame.
      final repo = FakeDocumentRepository(
        pages: const [
          PageImage(
            position: 1,
            imagePath: '/a.jpg',
            flatImagePath: '/a_flat.jpg',
          ),
        ],
      );
      await tester.pumpWidget(
        localizedTestApp(
          home: PageViewerScreen(documentId: 1, name: 'D', repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      Key? pageImageKey() => tester
          .widget<Image>(
            find.descendant(
              of: find.byKey(const Key('page-viewer-page-1')),
              matching: find.byType(Image),
            ),
          )
          .key;

      final before = pageImageKey();
      expect(before, isNotNull, reason: 'image must carry a versioned key');

      await tester.tap(find.byKey(const Key('page-viewer-rotate')));
      await tester.pumpAndSettle();

      final after = pageImageKey();
      expect(
        after,
        isNot(before),
        reason: 'a same-path regenerated flat must force a fresh decode',
      );
    },
  );
}
