import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> pushViewer(WidgetTester tester, FakeDocumentRepository repo) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            key: const Key('open'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => PageViewerScreen(
                    documentId: 1, name: 'Doc', repository: repo),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ));
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

  testWidgets('overflow menu exposes Export as image', (tester) async {
    await pushViewer(tester, twoPageRepo());
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('page-viewer-export-image')), findsOneWidget);
  });

  testWidgets('exporting the current page calls exportPageAsImage + confirms',
      (tester) async {
    final repo = twoPageRepo();
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(repo.lastExportedImagePosition, 1);
    expect(find.text('Page saved as image'), findsOneWidget);
  });

  testWidgets('export failure shows an error SnackBar', (tester) async {
    final repo = twoPageRepo(throwOnExportImage: true);
    await pushViewer(tester, repo);
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-export-image')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-original')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't export image"), findsOneWidget);
  });
}
