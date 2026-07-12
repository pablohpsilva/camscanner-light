import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/widgets/page_thumbnail_strip.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import '../../../support/ream_pump.dart';

void main() {
  final pages = [
    const PageImage(position: 1, imagePath: '/nonexistent/h2p1.jpg'),
    const PageImage(position: 2, imagePath: '/nonexistent/h2p2.jpg'),
    const PageImage(position: 3, imagePath: '/nonexistent/h2p3.jpg'),
  ];

  Future<void> pump(
    WidgetTester tester, {
    List<PageImage>? p,
    int current = 0,
    void Function(int)? onTap,
    void Function(int, int)? onReorder,
  }) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: PageThumbnailStrip(
          pages: p ?? pages,
          currentIndex: current,
          onTap: onTap ?? (_) {},
          onReorder: onReorder,
        ),
      ),
    ),
  );

  testWidgets('ListView has key page-thumbnail-strip', (tester) async {
    await pump(tester);
    await tester.pump();
    expect(find.byKey(const Key('page-thumbnail-strip')), findsOneWidget);
  });

  testWidgets('renders one tile per page with the correct 0-based key', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    expect(find.byKey(const Key('page-thumb-0')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-1')), findsOneWidget);
    expect(find.byKey(const Key('page-thumb-2')), findsOneWidget);
  });

  testWidgets('current tile has a border; non-current tiles do not', (
    tester,
  ) async {
    await pump(tester, current: 1);
    await tester.pump();

    final selected = tester.widget<Container>(
      find.byKey(const Key('page-thumb-1')),
    );
    final decoration = selected.foregroundDecoration as BoxDecoration?;
    expect(
      decoration?.border,
      isNotNull,
      reason: 'selected tile must have a border',
    );

    final notSelected = tester.widget<Container>(
      find.byKey(const Key('page-thumb-0')),
    );
    expect(
      notSelected.foregroundDecoration,
      isNull,
      reason: 'non-selected tile must have no border',
    );
  });

  testWidgets('tapping tile i calls onTap(i)', (tester) async {
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    await tester.pump();

    await tester.tap(find.byKey(const Key('page-thumb-2')));
    await tester.pump();

    expect(tapped, 2);
  });

  testWidgets('tapping tile 0 calls onTap(0)', (tester) async {
    int? tapped;
    await pump(tester, onTap: (i) => tapped = i);
    await tester.pump();

    await tester.tap(find.byKey(const Key('page-thumb-0')));
    await tester.pump();

    expect(tapped, 0);
  });

  // IMPORTANT: On host, Image.file with a non-loadable path does NOT hang and does NOT
  // fire errorBuilder inside FakeAsync. Asserting cacheWidth and errorBuilder is the
  // deterministic wiring check; actual image rendering is verified on-device.
  testWidgets(
    'each visible tile uses a downsampled Image.file with errorBuilder',
    (tester) async {
      await pump(tester);
      await tester.pump();
      final imgs = tester.widgetList<Image>(find.byType(Image)).toList();
      expect(imgs, isNotEmpty);
      expect(
        imgs.first.image,
        isA<ResizeImage>(),
        reason: 'cacheWidth set → ResizeImage wraps FileImage',
      );
      expect(imgs.first.errorBuilder, isNotNull);
    },
  );

  testWidgets('onReorder provided → ReorderableListView is rendered', (
    tester,
  ) async {
    await pump(tester, onReorder: (_, _) {});
    await tester.pump();
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('onReorder null → ListView is rendered (default)', (
    tester,
  ) async {
    await pump(tester);
    await tester.pump();
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(ReorderableListView), findsNothing);
  });

  testWidgets(
    'selected tile border color is ReamColors.dark.green under ReamTheme.dark()',
    (tester) async {
      await pumpReam(
        tester,
        PageThumbnailStrip(pages: pages, currentIndex: 1, onTap: (_) {}),
        theme: ReamTheme.dark(),
      );
      await tester.pump();

      final selected = tester.widget<Container>(
        find.byKey(const Key('page-thumb-1')),
      );
      final decoration = selected.foregroundDecoration as BoxDecoration?;
      final border = decoration?.border as Border?;
      expect(
        border?.top.color,
        ReamColors.dark.green,
        reason: 'active tile border must use ReamColors.dark.green',
      );
    },
  );
}
