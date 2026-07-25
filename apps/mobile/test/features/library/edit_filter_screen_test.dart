import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/edit_filter_screen.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/image_enhancer.dart';

import '../../support/localized_app.dart';

// B3: a fast, host-safe enhancer that returns fixed bytes (no compute isolate).
class _FakeEnhancer implements ImageEnhancer {
  _FakeEnhancer(this.out);
  final Uint8List out;
  @override
  Future<Uint8List> enhance(Uint8List bytes) async => out;
}

void main() {
  testWidgets('shows the filter strip and returns the selected mode on Save', (
    tester,
  ) async {
    EnhancerMode? popped;
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<EnhancerMode>(
                    MaterialPageRoute<EnhancerMode>(
                      builder: (_) => const EditFilterScreen(
                        // Deliberately non-loadable path: no host Image decode.
                        imagePath: '/nonexistent/base.jpg',
                        initialMode: EnhancerMode.none,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget);

    // Pick grayscale, then Save.
    await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('edit-filter-save')));
    await tester.pumpAndSettle();

    expect(popped, EnhancerMode.grayscale);
  });

  testWidgets('back returns null (no change)', (tester) async {
    EnhancerMode? popped = EnhancerMode.auto; // sentinel to detect null
    await tester.pumpWidget(
      localizedTestApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popped = await Navigator.of(context).push<EnhancerMode>(
                    MaterialPageRoute<EnhancerMode>(
                      builder: (_) => const EditFilterScreen(
                        imagePath: '/nonexistent/base.jpg',
                        initialMode: EnhancerMode.auto,
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('edit-filter-cancel')));
    await tester.pumpAndSettle();

    expect(popped, isNull);
  });

  // ── B3: live filter preview on the base image ────────────────────────────
  // readBytes returns Uint8List(0): length < 20 so FilterPickerStrip skips its
  // thumbnail compute() (no host deadlock), while _sourceBytes is non-null so
  // the injected preview seams run.
  group('B3 live preview', () {
    final previewBytes = Uint8List.fromList(const [1, 2, 3, 4, 5]);

    Widget host({Duration debounce = Duration.zero}) => localizedTestApp(
      home: EditFilterScreen(
        imagePath: '/nonexistent/base.jpg',
        initialMode: EnhancerMode.none,
        readBytes: (_) async => Uint8List(0),
        previewDebounce: debounce,
        proxyRunner: (b) async => b,
        previewEnhancerFor: (_) => _FakeEnhancer(previewBytes),
      ),
    );

    testWidgets('base image starts as the raw file image', (tester) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();
      final image = tester.widget<Image>(
        find.byKey(const Key('edit-filter-image')),
      );
      expect(image.image, isA<FileImage>());
    });

    testWidgets(
      'selecting a filter swaps the base to an Image.memory preview',
      (tester) async {
        await tester.pumpWidget(host());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
        await tester.pump(); // onModeChanged -> schedule + spinner
        await tester.pump(const Duration(milliseconds: 10)); // fire timer
        await tester.pump(); // proxyRunner future
        await tester.pump(); // enhance future
        await tester.pump(); // setState(_previewBytes)

        final image = tester.widget<Image>(
          find.byKey(const Key('edit-filter-image')),
        );
        expect(image.image, isA<MemoryImage>());
      },
    );

    testWidgets('selecting Original returns to the raw file image', (
      tester,
    ) async {
      await tester.pumpWidget(host());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        tester.widget<Image>(find.byKey(const Key('edit-filter-image'))).image,
        isA<MemoryImage>(),
      );

      await tester.tap(find.byKey(const Key('filter-tile-original')));
      await tester.pump();
      expect(
        tester.widget<Image>(find.byKey(const Key('edit-filter-image'))).image,
        isA<FileImage>(),
      );
    });

    testWidgets('shows a spinner while the preview is computing', (
      tester,
    ) async {
      final gate = Completer<Uint8List>();
      await tester.pumpWidget(
        localizedTestApp(
          home: EditFilterScreen(
            imagePath: '/nonexistent/base.jpg',
            initialMode: EnhancerMode.none,
            readBytes: (_) async => Uint8List(0),
            previewDebounce: Duration.zero,
            proxyRunner: (_) => gate.future, // stalls the compute
            previewEnhancerFor: (_) => _FakeEnhancer(previewBytes),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-tile-color')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(
        find.byKey(const Key('edit-filter-preview-loading')),
        findsOneWidget,
      );

      gate.complete(Uint8List(0));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(
        find.byKey(const Key('edit-filter-preview-loading')),
        findsNothing,
      );
    });

    testWidgets('Save still returns the selected mode (not the preview)', (
      tester,
    ) async {
      EnhancerMode? popped;
      await tester.pumpWidget(
        localizedTestApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await Navigator.of(context).push<EnhancerMode>(
                      MaterialPageRoute<EnhancerMode>(
                        builder: (_) => EditFilterScreen(
                          imagePath: '/nonexistent/base.jpg',
                          initialMode: EnhancerMode.none,
                          readBytes: (_) async => Uint8List(0),
                          previewDebounce: Duration.zero,
                          proxyRunner: (b) async => b,
                          previewEnhancerFor: (_) =>
                              _FakeEnhancer(previewBytes),
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit-filter-save')));
      await tester.pumpAndSettle();

      expect(popped, EnhancerMode.grayscale);
    });
  });
}
