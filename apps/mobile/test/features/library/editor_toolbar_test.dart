import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/editor_toolbar.dart';
import 'package:mobile/theme/ream_theme.dart';
import '../../support/ream_pump.dart';

void main() {
  group('EditorToolbar', () {
    testWidgets('renders all 6 keyed buttons with their labels', (
      tester,
    ) async {
      await pumpReam(
        tester,
        EditorToolbar(
          onCrop: () {},
          onRotate: () {},
          onText: () {},
          onRetake: () {},
          onShare: () {},
          onDelete: () {},
        ),
        theme: ReamTheme.dark(),
      );

      expect(find.byKey(const Key('page-viewer-edit')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-rotate')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-view-text')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-retake')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-share')), findsOneWidget);
      expect(find.byKey(const Key('page-viewer-delete-page')), findsOneWidget);

      expect(find.text('Crop'), findsOneWidget);
      expect(find.text('Rotate'), findsOneWidget);
      expect(find.text('Text'), findsOneWidget);
      expect(find.text('Retake'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    testWidgets('tapping rotate fires onRotate', (tester) async {
      var rotateCount = 0;
      await pumpReam(
        tester,
        EditorToolbar(
          onCrop: () {},
          onRotate: () => rotateCount++,
          onText: () {},
          onRetake: () {},
          onShare: () {},
          onDelete: () {},
        ),
        theme: ReamTheme.dark(),
      );

      await tester.tap(find.byKey(const Key('page-viewer-rotate')));
      await tester.pump();

      expect(rotateCount, 1);
    });

    testWidgets('tapping delete fires onDelete', (tester) async {
      var deleteCount = 0;
      await pumpReam(
        tester,
        EditorToolbar(
          onCrop: () {},
          onRotate: () {},
          onText: () {},
          onRetake: () {},
          onShare: () {},
          onDelete: () => deleteCount++,
        ),
        theme: ReamTheme.dark(),
      );

      await tester.tap(find.byKey(const Key('page-viewer-delete-page')));
      await tester.pump();

      expect(deleteCount, 1);
    });

    testWidgets('null onCrop keeps page-viewer-edit present but inert', (
      tester,
    ) async {
      var cropCount = 0;
      await pumpReam(
        tester,
        EditorToolbar(
          onCrop: null,
          onRotate: () {},
          onText: () {},
          onRetake: () {},
          onShare: () {},
          onDelete: () {},
        ),
        theme: ReamTheme.dark(),
      );

      expect(find.byKey(const Key('page-viewer-edit')), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('page-viewer-edit')),
        warnIfMissed: false,
      );
      await tester.pump();

      expect(cropCount, 0);
    });
  });
}
