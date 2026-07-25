import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

import 'localized_app.dart';

/// Records which swipe / dialog handler last fired, so the swipe-actions BDD can
/// assert on the outcome without a real repository. Cleared by
/// [pumpSwipeableDocumentList].
final Set<String> swipeActionsFired = <String>{};

DocumentSummary _summary(int id) => DocumentSummary(
  document: Document(
    id: id,
    name: 'Doc $id',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  ),
  pageCount: 1,
  thumbnailPath: '/nonexistent/thumb-$id.jpg', // non-loadable on purpose
);

/// Pumps a [DocumentsListView] with one document and handlers that record into
/// [swipeActionsFired]. Shared by the host BDD (test/bdd) and the on-device BDD
/// (integration_test) — the swipe gesture is the native-touch-sensitive part
/// under test; persistence is covered by other integration features.
Future<void> pumpSwipeableDocumentList(WidgetTester tester) async {
  swipeActionsFired.clear();
  await tester.pumpWidget(
    localizedTestApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [_summary(1)],
          onOpen: (_) => swipeActionsFired.add('open'),
          onRename: (_) => swipeActionsFired.add('rename'),
          onShare: (_) => swipeActionsFired.add('share'),
          onCopyText: (_) => swipeActionsFired.add('copytext'),
          onProtect: (_) => swipeActionsFired.add('protect'),
          onDelete: (_) => swipeActionsFired.add('delete'),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
