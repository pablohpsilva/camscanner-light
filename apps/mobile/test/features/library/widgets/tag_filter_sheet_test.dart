import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/tag.dart';
import 'package:mobile/features/library/widgets/tag_filter_sheet.dart';

import '../../../support/ream_pump.dart';

void main() {
  Tag tag(int id, String name) =>
      Tag(id: id, name: name, createdAt: DateTime.utc(2026));

  final tags = [tag(1, 'Work'), tag(2, 'Personal'), tag(3, 'Urgent')];

  group('TagFilterSheet', () {
    testWidgets('renders a filter chip per tag', (tester) async {
      await pumpReam(
        tester,
        TagFilterSheet(tags: tags, initial: const {}, onDone: (_) {}),
      );

      expect(find.byType(FilterChip), findsNWidgets(3));
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
    });

    testWidgets('seeds selection state from initial', (tester) async {
      await pumpReam(
        tester,
        TagFilterSheet(tags: tags, initial: const {2}, onDone: (_) {}),
      );

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Personal'),
      );
      expect(chip.selected, true);

      final otherChip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Work'),
      );
      expect(otherChip.selected, false);
    });

    testWidgets('tapping a chip toggles its selection', (tester) async {
      await pumpReam(
        tester,
        TagFilterSheet(tags: tags, initial: const {}, onDone: (_) {}),
      );

      await tester.tap(find.widgetWithText(FilterChip, 'Work'));
      await tester.pump();

      final chip = tester.widget<FilterChip>(
        find.widgetWithText(FilterChip, 'Work'),
      );
      expect(chip.selected, true);
    });

    testWidgets('Done button calls onDone with the selected set', (
      tester,
    ) async {
      Set<int>? result;
      await pumpReam(
        tester,
        TagFilterSheet(
          tags: tags,
          initial: const {2},
          onDone: (s) => result = s,
        ),
      );

      await tester.tap(find.widgetWithText(FilterChip, 'Urgent'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('tag-filter-done')));
      await tester.pump();

      expect(result, {2, 3});
    });

    testWidgets('showTagFilterSheet returns the selected set on Done', (
      tester,
    ) async {
      Set<int>? result;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showTagFilterSheet(
                context,
                tags: tags,
                initial: const {1},
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilterChip, 'Personal'));
      await tester.pump();

      await tester.tap(find.byKey(const Key('tag-filter-done')));
      await tester.pumpAndSettle();

      expect(result, {1, 2});
    });
  });
}
