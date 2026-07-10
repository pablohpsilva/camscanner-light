import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

// All gallery paths are NON-LOADABLE: a real file routed through Image.file in
// a host widget test leaves a pending dart:io isolate-port read that never
// resolves under flutter_test's fake-async, hanging pumpAndSettle.  A bad path
// errors fast (no pending I/O) so the whole test suite stays instant.
ScanDependencies _deps({bool cancel = false, bool throwOnPick = false}) =>
    ScanDependencies(
      createGalleryPicker: () => FakeGalleryPicker(
        cancel: cancel,
        throwOnPick: throwOnPick,
        returnPath: '/nonexistent/import.jpg',
      ),
      createEdgeDetector: FakeEdgeDetector.new,
    );

void main() {
  Future<void> pumpHome(
    WidgetTester tester, {
    required FakeDocumentRepository repo,
    ScanDependencies? deps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: deps ?? _deps(),
          libraryDependencies: fakeLibraryDependencies(repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('home-import button is present in the action row', (
    tester,
  ) async {
    await pumpHome(tester, repo: FakeDocumentRepository());
    expect(find.byKey(const Key('home-import')), findsOneWidget);
  });

  testWidgets('tapping home-import opens CaptureReviewScreen', (tester) async {
    await pumpHome(tester, repo: FakeDocumentRepository());
    await tester.tap(find.byKey(const Key('home-import')));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureReviewScreen), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget);
  });

  testWidgets(
    'accepting in review calls createFromCapture once and returns to home',
    (tester) async {
      final repo = FakeDocumentRepository();
      await pumpHome(tester, repo: repo);
      await tester.tap(find.byKey(const Key('home-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();
      expect(
        repo.createCalls,
        1,
        reason: 'createFromCapture must be called exactly once on accept',
      );
      expect(
        find.byType(CaptureReviewScreen),
        findsNothing,
        reason: 'review screen is popped after save',
      );
    },
  );

  testWidgets('cancelling the picker stays on home — no review, no save', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await pumpHome(tester, repo: repo, deps: _deps(cancel: true));
    await tester.tap(find.byKey(const Key('home-import')));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureReviewScreen), findsNothing);
    expect(repo.createCalls, 0);
  });

  testWidgets('picker error shows a SnackBar and stays on home', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await pumpHome(tester, repo: repo, deps: _deps(throwOnPick: true));
    await tester.tap(find.byKey(const Key('home-import')));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't import photo"), findsOneWidget);
    expect(find.byType(CaptureReviewScreen), findsNothing);
  });
}
