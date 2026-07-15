import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/edit_filter_screen.dart';
import 'package:mobile/features/library/enhancer_mode.dart';

import '../../support/localized_app.dart';

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
}
