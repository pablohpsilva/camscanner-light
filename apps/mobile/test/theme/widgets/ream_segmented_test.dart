import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_segmented.dart';

void main() {
  testWidgets('expanded lays out full-width segments; tap fires onChanged', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: Scaffold(
          body: ReamSegmented<String>(
            expanded: true,
            value: 'bug',
            segments: const [
              ReamSegment(value: 'bug', label: 'Bug'),
              ReamSegment(value: 'idea', label: 'Idea'),
              ReamSegment(value: 'question', label: 'Question'),
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
