import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<FakeDocumentRepository> seededRepo() async {
    final repo = FakeDocumentRepository();
    final work = await repo.createTag('Work');
    await repo.createTag('Personal');
    final invoice = Document(
      id: 1,
      name: 'Invoice',
      createdAt: DateTime.utc(2026, 1, 1),
      modifiedAt: DateTime.utc(2026, 1, 1),
    );
    final recipe = Document(
      id: 2,
      name: 'Recipe',
      createdAt: DateTime.utc(2026, 1, 2),
      modifiedAt: DateTime.utc(2026, 1, 2),
    );
    repo.documents.addAll([recipe, invoice]);
    await repo.setDocumentTags(invoice.id, {work.id});
    return repo;
  }

  Future<void> pumpHome(
    WidgetTester tester,
    FakeDocumentRepository repo, {
    FeatureFlags features = const FeatureFlags(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            repo,
            features: features,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tag filter affordance hidden when there are no tags', (
    tester,
  ) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.byKey(const Key('tag-filter')), findsNothing);
  });

  testWidgets('tag filter affordance hidden when features.tags is off', (
    tester,
  ) async {
    await pumpHome(
      tester,
      await seededRepo(),
      features: const FeatureFlags(tags: false),
    );
    expect(find.byKey(const Key('tag-filter')), findsNothing);
  });

  testWidgets('tag filter affordance shown when tags exist and feature is on', (
    tester,
  ) async {
    await pumpHome(tester, await seededRepo());
    expect(find.byKey(const Key('tag-filter')), findsOneWidget);
  });

  testWidgets(
    'selecting a tag in the sheet filters the displayed documents (AND)',
    (tester) async {
      await pumpHome(tester, await seededRepo());

      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Recipe'), findsOneWidget);

      await tester.tap(find.byKey(const Key('tag-filter')));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Work'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('tag-filter-done')));
      await tester.pumpAndSettle();

      expect(find.text('Invoice'), findsOneWidget);
      expect(find.text('Recipe'), findsNothing);
    },
  );
}
