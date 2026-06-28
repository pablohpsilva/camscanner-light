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

  testWidgets('renders one tile per document with name, date and page count',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
            summaries: [summary(1), summary(2, pageCount: 3)]),
      ),
    ));
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
  });
}
