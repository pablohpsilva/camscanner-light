import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

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

Future<void> _pump(WidgetTester tester, {FeatureFlags? features}) async {
  final s = _summary();
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [s],
          onShare: (_) {},
          onRename: (_) {},
          features: features ?? const FeatureFlags(),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default flags hide fax but show share-link', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('document-1-fax')), findsNothing);
    expect(find.byKey(const Key('document-1-share-link')), findsOneWidget);
  });

  testWidgets('fax: true shows the fax item', (tester) async {
    await _pump(tester, features: const FeatureFlags(fax: true));
    expect(find.byKey(const Key('document-1-fax')), findsOneWidget);
  });

  testWidgets('shareLink: false hides the share-link item', (tester) async {
    await _pump(tester, features: const FeatureFlags(shareLink: false));
    expect(find.byKey(const Key('document-1-share-link')), findsNothing);
  });
}
