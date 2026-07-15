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
    // Non-loadable image path does not hang.
    await tester.pumpAndSettle();
  }

  testWidgets('all toolbar buttons present with default flags', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags());
    for (final key in const [
      'page-viewer-edit',
      'page-viewer-rotate',
      'page-viewer-filter',
      'page-viewer-view-text',
      'page-viewer-retake',
      'page-viewer-share',
      'page-viewer-delete-page',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('crop off hides the crop button', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags(crop: false));
    expect(find.byKey(const Key('page-viewer-edit')), findsNothing);
    expect(find.byKey(const Key('page-viewer-rotate')), findsOneWidget);
  });

  testWidgets('share umbrella off hides the Share button', (tester) async {
    await pumpViewer(tester, features: const FeatureFlags(share: false));
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
  });

  testWidgets('share on but every sub-action off hides the Share button', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        exportPdf: false,
        shareImage: false,
        exportAllImages: false,
        print: false,
        protectWithPassword: false,
        shareLink: false,
        // fax already defaults false
      ),
    );
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
  });

  testWidgets('share stays visible when at least one sub-action is on', (
    tester,
  ) async {
    await pumpViewer(
      tester,
      features: const FeatureFlags(
        exportPdf: true,
        shareImage: false,
        exportAllImages: false,
        print: false,
        protectWithPassword: false,
        shareLink: false,
      ),
    );
    expect(find.byKey(const Key('page-viewer-share')), findsOneWidget);
  });
}
