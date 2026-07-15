import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../support/fake_library.dart';
import '../support/localized_app.dart';

/// Shared repo for H2 BDD steps — read by Then/When steps in this feature.
FakeDocumentRepository h2Repo = FakeDocumentRepository();

/// Usage: the page viewer is open with 2 pages
Future<void> thePageViewerIsOpenWith2Pages(WidgetTester tester) async {
  h2Repo = FakeDocumentRepository(
    pages: [
      const PageImage(position: 1, imagePath: '/nonexistent/h2bdd1.jpg'),
      const PageImage(position: 2, imagePath: '/nonexistent/h2bdd2.jpg'),
    ],
  );
  await tester.pumpWidget(
    localizedTestApp(
      home: PageViewerScreen(documentId: 1, name: 'H2 Doc', repository: h2Repo),
    ),
  );
  await tester.pumpAndSettle();
}
