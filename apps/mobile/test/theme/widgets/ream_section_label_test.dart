import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_section_label.dart';

void main() {
  testWidgets('uppercases the label and uses the mono font', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: const Scaffold(body: ReamSectionLabel('Quality')),
      ),
    );
    final text = tester.widget<Text>(find.text('QUALITY'));
    expect(text.style!.fontFamily, 'IBMPlexMono');
  });
}
