import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

/// The page viewer's FAILURE branches.
///
/// Every operation here already had a success test (page_viewer_split_test,
/// _merge_test, _rotate_test, _filter_test, _protect_test), but none drove the
/// repository into failure, so each `if (!ok && mounted) showErrorSnack(...)`
/// was uncovered by BOTH the host and the e2e suite.
///
/// These are worth testing on their own merits rather than for the line count:
/// the alternative to a visible error is a control that silently does nothing,
/// which is precisely how a broken write looks to a user. The `mounted` guard
/// in each branch also matters — showing a snackbar through a disposed context
/// throws — and it only ever executes on the failure path.
void main() {
  Document makeDoc(int id, String name) => Document(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 7, 1),
    modifiedAt: DateTime.utc(2026, 7, 1),
  );

  Future<void> pumpViewer(
    WidgetTester tester,
    FakeDocumentRepository repo,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 7, name: 'Doc', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
  }

  FakeDocumentRepository failingRepo() => FakeDocumentRepository(
    pages: const [
      PageImage(position: 1, imagePath: '/a.jpg'),
      PageImage(position: 2, imagePath: '/b.jpg'),
    ],
    throwOnUpdate: true,
  );

  Future<void> openPageMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
  }

  testWidgets('a failed split reports the error instead of failing silently', (
    tester,
  ) async {
    await pumpViewer(tester, failingRepo());
    await openPageMenu(tester);
    await tester.tap(find.byKey(const Key('page-viewer-split')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't split"), findsOneWidget);
  });

  testWidgets('a failed rotate reports the error', (tester) async {
    await pumpViewer(tester, failingRepo());
    await tester.tap(find.byKey(const Key('page-viewer-rotate')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't rotate"), findsOneWidget);
  });

  testWidgets('a failed merge reports the error', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [makeDoc(1, 'Alpha'), makeDoc(2, 'Beta')],
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
      throwOnUpdate: true,
    );
    await tester.pumpWidget(
      localizedTestApp(
        home: PageViewerScreen(documentId: 1, name: 'Alpha', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await openPageMenu(tester);
    await tester.tap(find.byKey(const Key('page-viewer-merge')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('merge-picker-item-2')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't merge"), findsOneWidget);
  });
}
