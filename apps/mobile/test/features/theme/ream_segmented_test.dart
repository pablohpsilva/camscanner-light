import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/widgets/ream_segmented.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('tapping a segment fires onChanged with its value', (
    tester,
  ) async {
    String value = 'list';
    await pumpReam(
      tester,
      StatefulBuilder(
        builder: (_, setState) {
          return ReamSegmented<String>(
            value: value,
            segments: const [
              ReamSegment(value: 'list', label: 'List'),
              ReamSegment(value: 'grid', label: 'Grid'),
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
}
