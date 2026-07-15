import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/l10n/l10n.dart';

DocumentSummary _summary(int id) => DocumentSummary(
  document: Document(
    id: id,
    name: 'Scan $id',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  ),
  pageCount: 1,
  thumbnailPath: '/nonexistent/thumb-$id.jpg',
);

void main() {
  testWidgets(
    'reserves bottom inset so the Scan FAB does not cover the last row',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DocumentsListView(
              summaries: [_summary(1), _summary(2)],
              onOpen: (_) {},
              onRename: (_) {},
            ),
          ),
        ),
      );

      final listView = tester.widget<ListView>(
        find.byKey(const Key('documents-list')),
      );
      final padding = listView.padding as EdgeInsets?;
      expect(padding, isNotNull);
      // At least one row's height of clearance so the last item's overflow menu
      // can be scrolled above the floating Scan button.
      expect(
        padding!.bottom,
        greaterThanOrEqualTo(DocumentsListView.fabBottomInset),
      );
      expect(DocumentsListView.fabBottomInset, greaterThanOrEqualTo(72));
    },
  );
}
