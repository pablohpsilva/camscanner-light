import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

DocumentSummary _summary() => DocumentSummary(
  document: Document(
    id: 1,
    name: 'Scan 2026-06-27 20.26.42',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  ),
  pageCount: 1,
  thumbnailPath: '/nonexistent/thumb-1.jpg',
);

void main() {
  testWidgets('per-document menu shows Fax → not available', (tester) async {
    final s = _summary();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentsListView(
            summaries: [s],
            onShare: (_) {},
            onRename: (_) {},
            features: const FeatureFlags(fax: true),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(Key('document-menu-${s.document.id}')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(Key('document-${s.document.id}-share-link')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(Key('document-${s.document.id}-fax')));
    await tester.pumpAndSettle();
    expect(find.text(kFaxUnavailableMessage), findsOneWidget);
  });
}
