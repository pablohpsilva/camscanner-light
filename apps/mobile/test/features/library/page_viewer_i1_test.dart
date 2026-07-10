import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> pushViewer(
    WidgetTester tester,
    FakeDocumentRepository repo,
    FakeShareChannel share,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('open'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PageViewerScreen(
                    documentId: 1,
                    name: 'Doc',
                    repository: repo,
                    share: share,
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository twoPageRepo({bool throwOnExportImage = false}) =>
      FakeDocumentRepository(
        throwOnExportImage: throwOnExportImage,
        pages: [
          const PageImage(position: 1, imagePath: '/nonexistent/p1.jpg'),
          const PageImage(position: 2, imagePath: '/nonexistent/p2.jpg'),
        ],
      );

  testWidgets('overflow menu exposes Share as image', (tester) async {
    await pushViewer(tester, twoPageRepo(), FakeShareChannel());
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-export-image')), findsOneWidget);
    expect(find.text('Share as image'), findsOneWidget);
  });

  testWidgets('sharing the current page exports it then shares the JPG', (
    tester,
  ) async {
    final repo = twoPageRepo();
    final share = FakeShareChannel();
    await pushViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(repo.lastExportedImagePosition, 1);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.jpg'));
    expect(share.lastSubject, 'Doc');
  });

  testWidgets('export failure shows a share error and does not share', (
    tester,
  ) async {
    final repo = twoPageRepo(throwOnExportImage: true);
    final share = FakeShareChannel();
    await pushViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(share.calls, 0);
    expect(find.text("Couldn't share image"), findsOneWidget);
  });

  testWidgets('a share failure (not export) shows the share error', (
    tester,
  ) async {
    final repo = twoPageRepo();
    final share = FakeShareChannel(throwOnShare: true);
    await pushViewer(tester, repo, share);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't share image"), findsOneWidget);
  });
}
