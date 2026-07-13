import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_grid_view.dart';

import '../../support/ream_pump.dart';

void main() {
  final summaryA = DocumentSummary(
    document: Document(
      id: 1,
      name: 'Alpha',
      createdAt: DateTime(2025, 1, 1),
      modifiedAt: DateTime(2025, 1, 2),
    ),
    pageCount: 2,
  );

  final summaryB = DocumentSummary(
    document: Document(
      id: 2,
      name: 'Beta',
      createdAt: DateTime(2025, 2, 1),
      modifiedAt: DateTime(2025, 2, 2),
    ),
    pageCount: 1,
  );

  group('DocumentsGridView', () {
    testWidgets('renders the grid root key and both card keys', (tester) async {
      await pumpReam(
        tester,
        DocumentsGridView(summaries: [summaryA, summaryB]),
      );

      expect(find.byKey(const Key('documents-grid')), findsOneWidget);
      expect(find.byKey(const Key('document-card-1')), findsOneWidget);
      expect(find.byKey(const Key('document-card-2')), findsOneWidget);
    });

    testWidgets('tapping a card calls onOpen with the correct summary', (
      tester,
    ) async {
      DocumentSummary? opened;

      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA, summaryB],
          onOpen: (s) => opened = s,
        ),
      );

      await tester.tap(find.byKey(const Key('document-card-1')));
      await tester.pump();

      expect(opened, same(summaryA));
    });

    testWidgets('in selection mode, tap calls onToggleSelect not onOpen', (
      tester,
    ) async {
      DocumentSummary? toggled;
      DocumentSummary? opened;

      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA, summaryB],
          selectionMode: true,
          onToggleSelect: (s) => toggled = s,
          onOpen: (s) => opened = s,
        ),
      );

      await tester.tap(find.byKey(const Key('document-card-2')));
      await tester.pump();

      expect(toggled, same(summaryB));
      expect(opened, isNull);
    });

    testWidgets('selected cards receive selected: true', (tester) async {
      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA, summaryB],
          selectionMode: true,
          selectedIds: {1},
        ),
      );

      // Verify both cards still render (no crash with selectedIds set).
      expect(find.byKey(const Key('document-card-1')), findsOneWidget);
      expect(find.byKey(const Key('document-card-2')), findsOneWidget);

      // The selected card (id=1) shows a check_circle icon; the other does not.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('long press calls onLongPress with the correct summary', (
      tester,
    ) async {
      DocumentSummary? longPressed;

      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA, summaryB],
          onLongPress: (s) => longPressed = s,
        ),
      );

      await tester.longPress(find.byKey(const Key('document-card-1')));
      await tester.pump();

      expect(longPressed, same(summaryA));
    });

    testWidgets('renders empty grid without error', (tester) async {
      await pumpReam(tester, const DocumentsGridView(summaries: []));

      expect(find.byKey(const Key('documents-grid')), findsOneWidget);
    });

    testWidgets('threads onMoveToFolder through to the card menu', (
      tester,
    ) async {
      DocumentSummary? moved;
      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA],
          onMoveToFolder: (s) => moved = s,
        ),
      );

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-move-1')));
      await tester.pumpAndSettle();

      expect(moved, same(summaryA));
    });

    testWidgets('threads onManageTags through to the card menu', (
      tester,
    ) async {
      DocumentSummary? tagged;
      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA],
          onManageTags: (s) => tagged = s,
        ),
      );

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-tags-1')));
      await tester.pumpAndSettle();

      expect(tagged, same(summaryA));
    });

    testWidgets('threads onRename/onShare through to the card menu', (
      tester,
    ) async {
      DocumentSummary? renamed;
      DocumentSummary? shared;
      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA],
          onRename: (s) => renamed = s,
          onShare: (s) => shared = s,
        ),
      );

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-rename-1')), findsOneWidget);
      expect(find.byKey(const Key('document-share-1')), findsOneWidget);

      await tester.tap(find.byKey(const Key('document-rename-1')));
      await tester.pumpAndSettle();
      expect(renamed, same(summaryA));

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-share-1')));
      await tester.pumpAndSettle();
      expect(shared, same(summaryA));
    });

    testWidgets('omits the card menu in selection mode', (tester) async {
      await pumpReam(
        tester,
        DocumentsGridView(
          summaries: [summaryA],
          selectionMode: true,
          onShare: (_) {},
        ),
      );

      expect(find.byKey(const Key('document-menu-1')), findsNothing);
    });
  });
}
