import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/edit_filter_screen.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  testWidgets('Filter button opens EditFilterScreen and applies the chosen '
      'mode via updatePageEnhancer', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(
          position: 1,
          imagePath: '/nonexistent/a.jpg',
          enhancerMode: EnhancerMode.none,
        ),
      ],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 1, name: 'D', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-filter')));
    await tester.pumpAndSettle();
    expect(find.byType(EditFilterScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-filter-save')));
    await tester.pumpAndSettle();

    expect(repo.updateEnhancerCalls, 1);
    expect(repo.lastEnhancerPosition, 1);
    expect(repo.lastEnhancerMode, EnhancerMode.grayscale);
  });

  testWidgets('Filter apply is single-flight (2nd rapid tap ignored while in '
      'flight)', (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/a.jpg')],
      gate: gate,
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 1, name: 'D', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    // Open, choose, Save → the edit gates (stays in flight).
    await tester.tap(find.byKey(const Key('page-viewer-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('edit-filter-save')));
    await tester.pump();
    expect(repo.updateEnhancerCalls, 1);

    // Busy overlay is up; a second Filter tap must not start another edit.
    await tester.tap(
      find.byKey(const Key('page-viewer-filter')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(repo.updateEnhancerCalls, 1);

    gate.complete();
    await tester.pumpAndSettle();
  });
}
