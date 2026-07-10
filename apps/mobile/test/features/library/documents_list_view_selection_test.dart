import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

DocumentSummary _summary(int id, String name) => DocumentSummary(
  document: Document(
    id: id,
    name: name,
    createdAt: DateTime.utc(2026, 7, 6),
    modifiedAt: DateTime.utc(2026, 7, 6),
  ),
  pageCount: 1,
  thumbnailPath: '/nonexistent/thumb-$id.jpg',
);

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  final docs = [_summary(1, 'Alpha'), _summary(2, 'Beta')];

  testWidgets('long-press reports the row without opening it', (tester) async {
    DocumentSummary? longPressed;
    DocumentSummary? opened;
    await tester.pumpWidget(
      _host(
        DocumentsListView(
          summaries: docs,
          onOpen: (s) => opened = s,
          onLongPress: (s) => longPressed = s,
        ),
      ),
    );
    await tester.longPress(find.byKey(const Key('document-tile-1')));
    expect(longPressed?.document.id, 1);
    expect(opened, isNull);
  });

  testWidgets('in selection mode a tap toggles instead of opening', (
    tester,
  ) async {
    DocumentSummary? toggled;
    DocumentSummary? opened;
    await tester.pumpWidget(
      _host(
        DocumentsListView(
          summaries: docs,
          selectionMode: true,
          selectedIds: const {1},
          onOpen: (s) => opened = s,
          onToggleSelect: (s) => toggled = s,
        ),
      ),
    );
    // Selected row shows its checkbox; overflow menu is hidden.
    expect(find.byKey(const Key('document-check-1')), findsOneWidget);
    expect(find.byKey(const Key('document-menu-1')), findsNothing);

    await tester.tap(find.byKey(const Key('document-tile-2')));
    expect(toggled?.document.id, 2);
    expect(opened, isNull);
  });
}
