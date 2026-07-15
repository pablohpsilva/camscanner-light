import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  Future<void> pumpViewer(
    WidgetTester tester, {
    required FeatureFlags features,
  }) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: features,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('overflow button present by default', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('page-viewer-page-menu')), findsOneWidget);
  });

  testWidgets('overflow button hidden when all four items are off', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        rename: false,
        merge: false,
        split: false,
        deleteDocument: false,
      ),
    );
    expect(find.byKey(const Key('page-viewer-page-menu')), findsNothing);
  });

  testWidgets('only enabled items appear in the opened menu', (tester) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(merge: false, split: false),
    );
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-rename')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-merge')), findsNothing);
    expect(find.byKey(const Key('page-viewer-split')), findsNothing);
  });
}
