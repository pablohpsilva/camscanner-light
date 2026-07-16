import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

import '../test/support/fake_library.dart';
import '../test/support/localized_app.dart';

/// P11 device verification: every share surface — rebuilt from the single
/// [ShareAction] model — opens, lists the correct enabled actions for the
/// default FeatureFlags, and dispatches (the unavailable-toast path) on a REAL
/// Android device AND a real iOS device. The export/share DATA path is covered
/// separately by r1/r2; here we prove the refactored UI renders + dispatches
/// on-device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  DocumentSummary summary() => DocumentSummary(
    document: Document(
      id: 1,
      name: 'Scan X',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    ),
    pageCount: 1,
    thumbnailPath: '/nonexistent/thumb-1.jpg',
  );

  testWidgets('page_viewer share sheet: all tiles + fax dispatches its toast', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')],
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(
          documentId: 1,
          name: 'Scan X',
          repository: repo,
          features: const FeatureFlags(fax: true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-share')));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byKey(const Key('page-viewer-fax')));
    await tester.pumpAndSettle();
    expect(find.text("Fax isn't available yet"), findsOneWidget);
  });

  testWidgets('documents_list_view popup: extras present + fax toast', (
    tester,
  ) async {
    final s = summary();
    await tester.pumpWidget(
      localizedTestApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [s],
            onShare: (_) {},
            onRename: (_) {},
            features: const FeatureFlags(fax: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(Key('document-menu-${s.document.id}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('document-${s.document.id}-share-link')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('document-${s.document.id}-fax')));
    await tester.pumpAndSettle();
    expect(find.text("Fax isn't available yet"), findsOneWidget);
  });

  testWidgets('share_menu_button popup: share + extras + fax toast', (
    tester,
  ) async {
    var shared = 0;
    await tester.pumpWidget(
      localizedTestApp(
        home: Scaffold(
          body: ShareMenuButton(
            buttonKey: const Key('btn'),
            onShare: () => shared++,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('btn')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('share-menu-share')), findsOneWidget);
    expect(find.byKey(const Key('share-menu-share-link')), findsOneWidget);
    await tester.tap(find.byKey(const Key('share-menu-fax')));
    await tester.pumpAndSettle();
    expect(find.text("Fax isn't available yet"), findsOneWidget);
    expect(shared, 0);
  });
}
