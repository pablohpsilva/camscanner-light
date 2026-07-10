import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

void main() {
  DocumentSummary summary(int id, {int pageCount = 1}) => DocumentSummary(
    document: Document(
      id: id,
      name: 'Scan 2026-06-27 20.26.42',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    ),
    pageCount: pageCount,
    thumbnailPath: '/nonexistent/thumb-$id.jpg', // non-loadable on purpose
  );

  testWidgets('renders one tile per document with name, date and page count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(1), summary(2, pageCount: 3)],
          ),
        ),
      ),
    );
    // Safe to settle ONLY because thumbnail paths are non-loadable (a real
    // loadable Image.file would hang host tests). Keep these paths non-loadable.
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-1')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-2')), findsOneWidget);
    expect(find.byKey(const Key('document-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('document-thumb-2')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNWidgets(2));
    expect(find.textContaining('· 1 page'), findsOneWidget);
    expect(find.textContaining('· 3 pages'), findsOneWidget);

    // Ream restyle: the meta line ("… · N pages") is a mono readout.
    final meta = tester.widget<Text>(find.textContaining('· 1 page'));
    expect(
      meta.style?.fontFamily,
      'IBMPlexMono',
      reason: 'page-count/date meta uses ReamTypography.mono',
    );
  });

  testWidgets('tapping a tile invokes onOpen with that summary', (
    tester,
  ) async {
    DocumentSummary? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(1), summary(2, pageCount: 3)],
            onOpen: (s) => opened = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(opened, isNotNull);
    expect(opened!.document.id, 2);
  });

  testWidgets('shows a per-document rename menu when onRename is set', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(summaries: [summary(1)], onRename: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-menu-1')), findsOneWidget);
  });

  testWidgets('omits the rename menu when onRename is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocumentsListView(summaries: [summary(1)])),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-menu-1')), findsNothing);
  });

  testWidgets('selecting Rename invokes onRename with that summary', (
    tester,
  ) async {
    DocumentSummary? renamed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(2)],
            onRename: (s) => renamed = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-2')));
    await tester.pumpAndSettle();
    expect(renamed, isNotNull);
    expect(renamed!.document.id, 2);
  });

  testWidgets('the rename menu carries a screen-reader tooltip', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(summaries: [summary(1)], onRename: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<PopupMenuButton<String>>(
            find.byKey(const Key('document-menu-1')),
          )
          .tooltip,
      'Document options',
    );
  });

  testWidgets('shows a Share item when onShare is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(summaries: [summary(1)], onShare: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-share-1')), findsOneWidget);
  });

  testWidgets('selecting Share invokes onShare with that summary', (
    tester,
  ) async {
    DocumentSummary? shared;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(2)],
            onShare: (s) => shared = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-2')));
    await tester.pumpAndSettle();
    expect(shared, isNotNull);
    expect(shared!.document.id, 2);
  });

  testWidgets('long-pressing a tile invokes onLongPress with that summary', (
    tester,
  ) async {
    DocumentSummary? pressed;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(1), summary(2)],
            onLongPress: (s) => pressed = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byKey(const Key('document-tile-2')));
    expect(pressed, isNotNull);
    expect(pressed!.document.id, 2);
  });

  testWidgets('in selection mode a tap toggles selection instead of opening', (
    tester,
  ) async {
    DocumentSummary? toggled;
    DocumentSummary? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [summary(1), summary(2)],
            selectionMode: true,
            selectedIds: const {1},
            onOpen: (s) => opened = s,
            onToggleSelect: (s) => toggled = s,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Check marks reflect selectedIds; the overflow menu is hidden.
    expect(find.byKey(const Key('document-check-1')), findsOneWidget);
    expect(find.byKey(const Key('document-check-2')), findsOneWidget);
    expect(find.byKey(const Key('document-menu-1')), findsNothing);

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(toggled, isNotNull);
    expect(toggled!.document.id, 2);
    expect(opened, isNull);
  });
}
