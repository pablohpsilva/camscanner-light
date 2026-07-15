import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/editor_toolbar.dart';
import 'package:mobile/theme/ream_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required Widget toolbar}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.dark(),
        home: Scaffold(bottomNavigationBar: toolbar),
      ),
    );
    await tester.pumpAndSettle();
  }

  EditorToolbar build({bool showCrop = true, bool showShare = true}) =>
      EditorToolbar(
        onCrop: () {},
        onRotate: () {},
        onText: () {},
        onRetake: () {},
        onShare: () {},
        onDelete: () {},
        onFilter: () {},
        showCrop: showCrop,
        showShare: showShare,
      );

  testWidgets('shows all seven buttons by default', (tester) async {
    await pump(tester, toolbar: build());
    for (final key in const [
      'page-viewer-edit',
      'page-viewer-rotate',
      'page-viewer-filter',
      'page-viewer-view-text',
      'page-viewer-retake',
      'page-viewer-share',
      'page-viewer-delete-page',
    ]) {
      expect(find.byKey(Key(key)), findsOneWidget, reason: key);
    }
  });

  testWidgets('hides the crop button when showCrop is false', (tester) async {
    await pump(tester, toolbar: build(showCrop: false));
    expect(find.byKey(const Key('page-viewer-edit')), findsNothing);
    // others remain
    expect(find.byKey(const Key('page-viewer-rotate')), findsOneWidget);
    expect(find.byKey(const Key('page-viewer-share')), findsOneWidget);
  });

  testWidgets('hides the share button when showShare is false', (tester) async {
    await pump(tester, toolbar: build(showShare: false));
    expect(find.byKey(const Key('page-viewer-share')), findsNothing);
    expect(find.byKey(const Key('page-viewer-edit')), findsOneWidget);
  });
}
