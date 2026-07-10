import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

class _OnePageRepo extends FakeDocumentRepository {
  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async => [
    PageImage(position: 1, imagePath: '/nonexistent/p.jpg'),
  ];
}

void main() {
  testWidgets('home screen shows the donation banner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DonationBanner), findsOneWidget);
  });

  testWidgets('page viewer shows the donation banner', (tester) async {
    final DocumentRepository repo = _OnePageRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: PageViewerScreen(documentId: 1, name: 'Scan X', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(DonationBanner), findsOneWidget);
  });
}
