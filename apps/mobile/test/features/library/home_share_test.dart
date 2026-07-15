import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/localized_app.dart';

void main() {
  HomeScreen homeWith(FakeDocumentRepository repo, FakeShareChannel share) =>
      HomeScreen(
        libraryDependencies: LibraryDependencies(
          createRepository: () async => repo,
          share: share,
        ),
      );

  final doc = Document(
    id: 1,
    name: 'Report',
    createdAt: DateTime.utc(2026, 7, 2),
    modifiedAt: DateTime.utc(2026, 7, 2),
  );

  testWidgets(
    'Share on a document exports its PDF and hands it to the channel',
    (tester) async {
      final repo = FakeDocumentRepository(documents: [doc]);
      final share = FakeShareChannel();
      await tester.pumpWidget(localizedTestApp(home: homeWith(repo, share)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-share-1')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(repo.exportedIds, contains(1));
      expect(share.calls, 1);
      expect(share.lastFilePaths!.single, endsWith('.pdf'));
      expect(share.lastSubject, 'Report');
      expect(find.text("Couldn't share"), findsNothing);
    },
  );

  testWidgets('a failing channel shows a share error', (tester) async {
    final repo = FakeDocumentRepository(documents: [doc]);
    final share = FakeShareChannel(throwOnShare: true);
    await tester.pumpWidget(localizedTestApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share"), findsOneWidget);
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(documents: [doc], throwOnExport: true);
    final share = FakeShareChannel();
    await tester.pumpWidget(localizedTestApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share"), findsOneWidget);
  });

  testWidgets('double-tapping Share does not launch two exports', (
    tester,
  ) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(documents: [doc], exportGate: gate);
    final share = FakeShareChannel();
    await tester.pumpWidget(localizedTestApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    // First Share — blocks inside exportPdf on the gate.
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-1')));
    await tester.pump();

    // P04 T3: while the first share is in flight the busy overlay covers the
    // screen, so a second Share cannot be launched (re-entry is also guarded by
    // _sharing). The overlay's presence is what now prevents the double export.
    expect(find.byKey(const Key('home-sharing')), findsOneWidget);

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds.length, 1);
    expect(share.calls, 1);
  });
}
