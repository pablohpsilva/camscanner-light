import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/document_grid_card.dart';
import '../../support/ream_pump.dart';

DocumentSummary _summary() => DocumentSummary(
  document: Document(
    id: 7,
    name: 'Lease Agreement',
    createdAt: DateTime(2026, 7, 8),
    modifiedAt: DateTime(2026, 7, 8),
  ),
  pageCount: 6,
  thumbnailPath: null, // null path -> placeholder (no file I/O)
);

void main() {
  testWidgets('renders title, page/date meta, and fires onTap', (tester) async {
    var opened = false;
    await pumpReam(
      tester,
      DocumentGridCard(summary: _summary(), onTap: () => opened = true),
    );
    expect(find.text('Lease Agreement'), findsOneWidget);
    expect(find.textContaining('6'), findsWidgets); // "6p ·" meta
    await tester.tap(find.byKey(const Key('document-card-7')));
    expect(opened, true);
  });

  testWidgets('shows check badge when selected', (tester) async {
    await pumpReam(
      tester,
      DocumentGridCard(
        summary: _summary(),
        selected: true,
        selectionMode: true,
      ),
    );
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('fires onLongPress', (tester) async {
    var longPressed = false;
    await pumpReam(
      tester,
      DocumentGridCard(
        summary: _summary(),
        onLongPress: () => longPressed = true,
      ),
    );
    await tester.longPress(find.byKey(const Key('document-card-7')));
    expect(longPressed, true);
  });
}
