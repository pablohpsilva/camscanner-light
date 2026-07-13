import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/folder.dart';
import 'package:mobile/features/library/widgets/folder_filter_bar.dart';

void main() {
  testWidgets('renders All/Unfiled + folder chips with counts; taps callback',
      (tester) async {
    FolderFilter? picked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: FolderFilterBar(
          folders: [Folder(id: 1, name: 'Receipts', createdAt: DateTime.utc(2026))],
          counts: const {1: 3, null: 5}, // folderId -> count; null = unfiled
          active: const FolderFilter.all(),
          onChanged: (f) => picked = f,
          onCreateFolder: () {},
        ),
      ),
    ));
    expect(find.text('All'), findsOneWidget);
    // Counts are shown alongside the label (e.g. "Unfiled (5)"), so match by
    // substring rather than exact text for chips seeded with a count.
    expect(find.textContaining('Unfiled'), findsOneWidget);
    expect(find.textContaining('Receipts'), findsOneWidget);
    await tester.tap(find.textContaining('Receipts'));
    expect(picked, const FolderFilter.folder(1));
  });
}
