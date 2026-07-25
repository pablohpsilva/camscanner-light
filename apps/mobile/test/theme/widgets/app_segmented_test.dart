import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/widgets/app_segmented.dart';
import '../../support/app_pump.dart';

void main() {
  testWidgets('tapping a segment fires onChanged with its value', (
    tester,
  ) async {
    String value = 'list';
    await pumpApp(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          return AppSegmented<String>(
            value: value,
            segments: const [
              AppSegment(value: 'list', label: 'List'),
              AppSegment(value: 'grid', label: 'Grid'),
            ],
            onChanged: (v) => setState(() => value = v),
          );
        },
      ),
    );
    await tester.tap(find.byKey(const Key('segment-grid')));
    await tester.pump();
    expect(value, 'grid');
  });

  testWidgets('expanded lays out full-width segments; tap fires onChanged', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: AppSegmented<String>(
            expanded: true,
            value: 'bug',
            segments: const [
              AppSegment(value: 'bug', label: 'Bug'),
              AppSegment(value: 'idea', label: 'Idea'),
              AppSegment(value: 'question', label: 'Question'),
            ],
            onChanged: (v) => picked = v,
          ),
        ),
      ),
    );
    expect(find.byType(Expanded), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('segment-idea')));
    expect(picked, 'idea');
  });
}
