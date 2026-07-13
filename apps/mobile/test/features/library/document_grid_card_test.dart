import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/widgets/document_grid_card.dart';
import 'package:mobile/theme/ream_colors.dart';
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

  testWidgets('placeholder thumbnail icon uses the Ream muted token', (
    tester,
  ) async {
    await pumpReam(tester, DocumentGridCard(summary: _summary()));
    final icon = tester.widget<Icon>(find.byIcon(Icons.description_outlined));
    expect(icon.color, ReamColors.light.muted);
  });

  testWidgets('omits the overflow menu when no menu callback is set', (
    tester,
  ) async {
    await pumpReam(tester, DocumentGridCard(summary: _summary()));
    expect(find.byKey(const Key('document-menu-7')), findsNothing);
  });

  testWidgets('shows a Share item when onShare is set', (tester) async {
    await pumpReam(
      tester,
      DocumentGridCard(summary: _summary(), onShare: (_) {}),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-share-7')), findsOneWidget);
  });

  testWidgets('selecting Share invokes onShare with the summary', (
    tester,
  ) async {
    var s = _summary();
    dynamic shared;
    await pumpReam(
      tester,
      DocumentGridCard(summary: s, onShare: (v) => shared = v),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-share-7')));
    await tester.pumpAndSettle();
    expect(shared, same(s));
  });

  testWidgets('shows a Rename item when onRename is set', (tester) async {
    await pumpReam(
      tester,
      DocumentGridCard(summary: _summary(), onRename: (_) {}),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-rename-7')), findsOneWidget);
  });

  testWidgets('selecting Rename invokes onRename with the summary', (
    tester,
  ) async {
    var s = _summary();
    dynamic renamed;
    await pumpReam(
      tester,
      DocumentGridCard(summary: s, onRename: (v) => renamed = v),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-7')));
    await tester.pumpAndSettle();
    expect(renamed, same(s));
  });

  testWidgets(
    'shows Move to folder when features.folders and onMoveToFolder set',
    (tester) async {
      await pumpReam(
        tester,
        DocumentGridCard(summary: _summary(), onMoveToFolder: (_) {}),
      );
      await tester.tap(find.byKey(const Key('document-menu-7')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('document-move-7')), findsOneWidget);
    },
  );

  testWidgets('selecting Move to folder invokes onMoveToFolder with the summary', (
    tester,
  ) async {
    var s = _summary();
    dynamic moved;
    await pumpReam(
      tester,
      DocumentGridCard(summary: s, onMoveToFolder: (v) => moved = v),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-move-7')));
    await tester.pumpAndSettle();
    expect(moved, same(s));
  });

  testWidgets('hides Move to folder when features.folders is off', (
    tester,
  ) async {
    await pumpReam(
      tester,
      DocumentGridCard(
        summary: _summary(),
        onShare: (_) {},
        onMoveToFolder: (_) {},
        features: const FeatureFlags(folders: false),
      ),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-move-7')), findsNothing);
  });

  testWidgets('shows Tags when features.tags and onManageTags set', (
    tester,
  ) async {
    await pumpReam(
      tester,
      DocumentGridCard(summary: _summary(), onManageTags: (_) {}),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-tags-7')), findsOneWidget);
  });

  testWidgets('selecting Tags invokes onManageTags with the summary', (
    tester,
  ) async {
    var s = _summary();
    dynamic tagged;
    await pumpReam(
      tester,
      DocumentGridCard(summary: s, onManageTags: (v) => tagged = v),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tags-7')));
    await tester.pumpAndSettle();
    expect(tagged, same(s));
  });

  testWidgets('hides Tags when features.tags is off', (tester) async {
    await pumpReam(
      tester,
      DocumentGridCard(
        summary: _summary(),
        onShare: (_) {},
        onManageTags: (_) {},
        features: const FeatureFlags(tags: false),
      ),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-tags-7')), findsNothing);
  });

  testWidgets('the overflow menu tap does not also fire onTap', (
    tester,
  ) async {
    var opened = false;
    await pumpReam(
      tester,
      DocumentGridCard(
        summary: _summary(),
        onTap: () => opened = true,
        onShare: (_) {},
      ),
    );
    await tester.tap(find.byKey(const Key('document-menu-7')));
    await tester.pumpAndSettle();
    expect(opened, false);
  });
}
