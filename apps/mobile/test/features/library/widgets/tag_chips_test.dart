import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/tag.dart';
import 'package:mobile/features/library/widgets/tag_chips.dart';

import '../../../support/ream_pump.dart';

void main() {
  Tag tag(int id, String name) =>
      Tag(id: id, name: name, createdAt: DateTime.utc(2026));

  group('TagChips', () {
    testWidgets('renders nothing when tags is empty', (tester) async {
      await pumpReam(tester, const TagChips(tags: []));

      expect(find.byType(TagChips), findsOneWidget);
      expect(find.byType(Chip), findsNothing);
      expect(find.byType(SizedBox), findsWidgets);
    });

    testWidgets('renders one chip per tag with its name', (tester) async {
      await pumpReam(
        tester,
        TagChips(tags: [tag(1, 'Work'), tag(2, 'Urgent')]),
      );

      expect(find.byType(Chip), findsNWidgets(2));
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('Urgent'), findsOneWidget);
    });

    testWidgets('lays out chips in a Wrap', (tester) async {
      await pumpReam(tester, TagChips(tags: [tag(1, 'Work')]));

      expect(find.byType(Wrap), findsOneWidget);
    });
  });
}
