import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/widgets/documents_grid_view.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/l10n/l10n.dart';

void main() {
  DocumentSummary summary(int id) => DocumentSummary(
    document: Document(
      id: id,
      name: 'Doc $id',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    ),
    pageCount: 1,
    thumbnailPath: '/nonexistent/thumb-$id.jpg', // non-loadable on purpose
  );

  // Records which handler fired last for the given id.
  final fired = <String, int>{};

  Future<void> pump(
    WidgetTester tester, {
    FeatureFlags features = const FeatureFlags(),
    List<int> ids = const [1],
  }) async {
    fired.clear();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: DocumentsListView(
            summaries: ids.map(summary).toList(),
            features: features,
            onOpen: (s) => fired['open'] = s.document.id,
            onRename: (s) => fired['rename'] = s.document.id,
            onShare: (s) => fired['share'] = s.document.id,
            onCopyText: (s) => fired['copytext'] = s.document.id,
            onProtect: (s) => fired['protect'] = s.document.id,
            onDelete: (s) => fired['delete'] = s.document.id,
          ),
        ),
      ),
    );
    // Safe to settle: thumbnail paths are non-loadable.
    await tester.pumpAndSettle();
  }

  Future<void> swipeRight(WidgetTester tester, int id) async {
    await tester.drag(
      find.byKey(Key('document-slidable-$id')),
      const Offset(600, 0),
    );
    await tester.pumpAndSettle();
  }

  Future<void> swipeLeft(WidgetTester tester, int id) async {
    await tester.drag(
      find.byKey(Key('document-slidable-$id')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();
  }

  group('3-dots menu: Share with password (C4b)', () {
    testWidgets('shows the protect item when onProtect set and flag on', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-protect-1')), findsOneWidget);
    });

    testWidgets('selecting Share with password invokes onProtect', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-protect-1')));
      await tester.pumpAndSettle();
      expect(fired['protect'], 1);
    });

    testWidgets('omits the protect item when protectWithPassword is off', (
      tester,
    ) async {
      await pump(
        tester,
        features: const FeatureFlags(protectWithPassword: false),
      );
      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-protect-1')), findsNothing);
      // The existing items are still present.
      expect(find.byKey(const Key('document-share-1')), findsOneWidget);
      expect(find.byKey(const Key('document-rename-1')), findsOneWidget);
    });
  });

  group('swipe-right reveals four actions (C5)', () {
    testWidgets('each action key is present after swiping right', (
      tester,
    ) async {
      await pump(tester);
      await swipeRight(tester, 1);
      expect(find.byKey(const Key('document-slide-rename-1')), findsOneWidget);
      expect(
        find.byKey(const Key('document-slide-copytext-1')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('document-slide-share-1')), findsOneWidget);
      expect(find.byKey(const Key('document-slide-protect-1')), findsOneWidget);
    });

    testWidgets('tapping slide Rename fires onRename', (tester) async {
      await pump(tester);
      await swipeRight(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-rename-1')));
      await tester.pumpAndSettle();
      expect(fired['rename'], 1);
    });

    testWidgets('tapping slide Copy text fires onCopyText', (tester) async {
      await pump(tester);
      await swipeRight(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-copytext-1')));
      await tester.pumpAndSettle();
      expect(fired['copytext'], 1);
    });

    testWidgets('tapping slide Share fires onShare', (tester) async {
      await pump(tester);
      await swipeRight(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-share-1')));
      await tester.pumpAndSettle();
      expect(fired['share'], 1);
    });

    testWidgets('tapping slide Share with password fires onProtect', (
      tester,
    ) async {
      await pump(tester);
      await swipeRight(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-protect-1')));
      await tester.pumpAndSettle();
      expect(fired['protect'], 1);
    });

    testWidgets('a disabled feature flag hides its slide action', (
      tester,
    ) async {
      await pump(
        tester,
        features: const FeatureFlags(protectWithPassword: false),
      );
      await swipeRight(tester, 1);
      expect(find.byKey(const Key('document-slide-protect-1')), findsNothing);
      expect(find.byKey(const Key('document-slide-rename-1')), findsOneWidget);
    });
  });

  group('swipe-left → delete with confirm (C5)', () {
    testWidgets('reveals a delete action that opens a confirm dialog', (
      tester,
    ) async {
      await pump(tester);
      await swipeLeft(tester, 1);
      expect(find.byKey(const Key('document-slide-delete-1')), findsOneWidget);
      // No deletion yet.
      expect(fired.containsKey('delete'), isFalse);
      await tester.tap(find.byKey(const Key('document-slide-delete-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-delete-dialog')), findsOneWidget);
      // Still no deletion until confirmed.
      expect(fired.containsKey('delete'), isFalse);
    });

    testWidgets('confirming the dialog fires onDelete', (tester) async {
      await pump(tester);
      await swipeLeft(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-delete-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-delete-confirm')));
      await tester.pumpAndSettle();
      expect(fired['delete'], 1);
    });

    testWidgets('cancelling the dialog does NOT fire onDelete', (tester) async {
      await pump(tester);
      await swipeLeft(tester, 1);
      await tester.tap(find.byKey(const Key('document-slide-delete-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-delete-cancel')));
      await tester.pumpAndSettle();
      expect(fired.containsKey('delete'), isFalse);
    });
  });

  group('other surfaces unaffected', () {
    testWidgets('the 3-dots menu still opens and Rename still fires', (
      tester,
    ) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-rename-1')));
      await tester.pumpAndSettle();
      expect(fired['rename'], 1);
    });

    testWidgets('a plain tap still opens the document', (tester) async {
      await pump(tester);
      await tester.tap(find.byKey(const Key('document-tile-1')));
      await tester.pumpAndSettle();
      expect(fired['open'], 1);
    });

    testWidgets('grid view has no Slidable', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DocumentsGridView(
              summaries: [summary(1)],
              onOpen: (_) {},
              onRename: (_) {},
              onShare: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-slidable-1')), findsNothing);
    });

    testWidgets('selection mode shows no slidable (checkbox row instead)', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DocumentsListView(
              summaries: [summary(1)],
              selectionMode: true,
              selectedIds: const {1},
              onDelete: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-slidable-1')), findsNothing);
      expect(find.byKey(const Key('document-check-1')), findsOneWidget);
    });
  });
}
