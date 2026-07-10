import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> theSecondPageThumbnailIsDraggedToTheFirstPosition(
  WidgetTester tester,
) async {
  final rlv = tester.widget<ReorderableListView>(
    find.byType(ReorderableListView),
  );
  rlv.onReorderItem!(1, 0);
  await tester.pumpAndSettle();
}
