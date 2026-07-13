import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/tag.dart';
import 'package:mobile/features/library/widgets/manage_tags_sheet.dart';

import '../../../support/ream_pump.dart';

void main() {
  Tag tag(int id, String name) =>
      Tag(id: id, name: name, createdAt: DateTime.utc(2026));

  final tags = [tag(1, 'Work'), tag(2, 'Personal'), tag(3, 'Urgent')];

  group('ManageTagsSheet', () {
    testWidgets('renders a chip per tag, plus a New tag affordance', (
      tester,
    ) async {
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageTagsSheet(
              context,
              tags: tags,
              initial: const {},
              onCreateTag: (name) async =>
                  Tag(id: 99, name: name, createdAt: DateTime.utc(2026)),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manage-tag-chip-1')), findsOneWidget);
      expect(find.byKey(const Key('manage-tag-chip-2')), findsOneWidget);
      expect(find.byKey(const Key('manage-tag-chip-3')), findsOneWidget);
      expect(find.byKey(const Key('manage-tags-new')), findsOneWidget);
      expect(find.byKey(const Key('manage-tags-done')), findsOneWidget);
    });

    testWidgets('seeds selection state from initial (document current tags)', (
      tester,
    ) async {
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageTagsSheet(
              context,
              tags: tags,
              initial: const {2},
              onCreateTag: (name) async =>
                  Tag(id: 99, name: name, createdAt: DateTime.utc(2026)),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final chip = tester.widget<FilterChip>(
        find.byKey(const Key('manage-tag-chip-2')),
      );
      expect(chip.selected, true);

      final otherChip = tester.widget<FilterChip>(
        find.byKey(const Key('manage-tag-chip-1')),
      );
      expect(otherChip.selected, false);
    });

    testWidgets('tapping a chip toggles its selection', (tester) async {
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showManageTagsSheet(
              context,
              tags: tags,
              initial: const {},
              onCreateTag: (name) async =>
                  Tag(id: 99, name: name, createdAt: DateTime.utc(2026)),
            ),
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manage-tag-chip-1')));
      await tester.pump();

      final chip = tester.widget<FilterChip>(
        find.byKey(const Key('manage-tag-chip-1')),
      );
      expect(chip.selected, true);
    });

    testWidgets('Done returns the selected set', (tester) async {
      Set<int>? result;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showManageTagsSheet(
                context,
                tags: tags,
                initial: const {2},
                onCreateTag: (name) async =>
                    Tag(id: 99, name: name, createdAt: DateTime.utc(2026)),
              );
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manage-tag-chip-3')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('manage-tags-done')));
      await tester.pumpAndSettle();

      expect(result, {2, 3});
    });

    testWidgets('dismissing without pressing Done returns null (cancelled)', (
      tester,
    ) async {
      Set<int>? result = const {999};
      var completed = false;
      await pumpReam(
        tester,
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showManageTagsSheet(
                context,
                tags: tags,
                initial: const {},
                onCreateTag: (name) async =>
                    Tag(id: 99, name: name, createdAt: DateTime.utc(2026)),
              );
              completed = true;
            },
            child: const Text('open'),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(20, 20)); // tap the scrim above the sheet
      await tester.pumpAndSettle();

      expect(completed, true);
      expect(result, isNull);
    });

    testWidgets(
      'New tag creates via the callback, adds it to the list, and selects it',
      (tester) async {
        Set<int>? result;
        var createdName = '';
        await pumpReam(
          tester,
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showManageTagsSheet(
                  context,
                  tags: tags,
                  initial: const {},
                  onCreateTag: (name) async {
                    createdName = name;
                    return Tag(
                      id: 42,
                      name: name,
                      createdAt: DateTime.utc(2026),
                    );
                  },
                );
              },
              child: const Text('open'),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('manage-tags-new')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('create-tag-field')),
          'Receipts',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('create-tag-save')));
        await tester.pumpAndSettle();

        expect(createdName, 'Receipts');
        expect(find.text('Receipts'), findsOneWidget);

        final chip = tester.widget<FilterChip>(
          find.byKey(const Key('manage-tag-chip-42')),
        );
        expect(chip.selected, true);

        await tester.tap(find.byKey(const Key('manage-tags-done')));
        await tester.pumpAndSettle();

        expect(result, contains(42));
      },
    );
  });
}
