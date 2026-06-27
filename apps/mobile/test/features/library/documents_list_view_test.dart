import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

void main() {
  Document doc(int id) => Document(
        id: id,
        name: 'Scan 2026-06-27 20.26.42',
        createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      );

  testWidgets('renders one tile per document with name + date', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DocumentsListView(documents: [doc(1), doc(2)])),
    ));
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-1')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-2')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNWidgets(2));
  });
}
