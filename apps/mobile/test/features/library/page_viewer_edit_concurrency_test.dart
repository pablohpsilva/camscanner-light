import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets(
    'rotate is single-flight: a 2nd tap while an edit is in flight is ignored',
    (tester) async {
      final gate = Completer<void>();
      final repo = FakeDocumentRepository(
        pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
        gate: gate,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
        ),
      );
      await tester.pumpAndSettle();

      // First tap: rotate begins and gates (stays in flight).
      await tester.tap(find.byKey(const Key('page-viewer-rotate')));
      await tester.pump();
      expect(repo.rotateCalls, 1);

      // A second rapid tap while the first edit is still in flight must NOT
      // start a second rotate — otherwise overlapping full-res regenerations
      // race and the image appears to "revert" (4x90 = 360).
      await tester.tap(
        find.byKey(const Key('page-viewer-rotate')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(
        repo.rotateCalls,
        1,
        reason: 'edits must be single-flight (toolbar disabled while busy)',
      );

      gate.complete();
      await tester.pumpAndSettle();
    },
  );
}
