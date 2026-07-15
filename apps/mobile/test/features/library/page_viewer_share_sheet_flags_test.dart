import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  Future<void> openShareSheet(
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
    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
  }

  testWidgets('all share tiles present by default (fax too, if fax on)', (
    tester,
  ) async {
    await openShareSheet(tester, features: const FeatureFlags(fax: true));
    for (final key in const [
      'page-viewer-export',
      'page-viewer-export-image',
      'page-viewer-export-all-images',
      'page-viewer-print',
      'page-viewer-protect',
      'page-viewer-share-link',
      'page-viewer-fax',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('fax defaults off — no fax tile', (tester) async {
    await openShareSheet(tester, features: const FeatureFlags());
    expect(find.byKey(const Key('page-viewer-fax')), findsNothing);
    expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
  });

  testWidgets('print off — no print tile, others remain', (tester) async {
    await openShareSheet(tester, features: const FeatureFlags(print: false));
    expect(find.byKey(const Key('page-viewer-print')), findsNothing);
    expect(find.byKey(const Key('page-viewer-export')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-protect')), findsOneWidget);
  });

  testWidgets('protect off — no protect tile', (tester) async {
    await openShareSheet(
      tester,
      features: const FeatureFlags(protectWithPassword: false),
    );
    expect(find.byKey(const Key('page-viewer-protect')), findsNothing);
  });
}
