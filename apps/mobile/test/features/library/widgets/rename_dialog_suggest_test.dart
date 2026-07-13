import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/rename_dialog.dart';

void main() {
  // Pump a trivial host with a button that opens the dialog and stores the
  // result, so each test can assert what showRenameDialog returned. Mirrors
  // rename_dialog_test.dart's pumpDialog helper, plus the optional [suggest].
  Future<void> pumpDialog(
    WidgetTester tester,
    String current, {
    required void Function(String?) onResult,
    Future<String?> Function()? suggest,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showRenameDialog(
                    context,
                    current,
                    suggest: suggest,
                  );
                  onResult(r);
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
  }

  testWidgets('shows a tappable suggestion chip that fills the field', (
    tester,
  ) async {
    String? result = '__unset__';
    await pumpDialog(
      tester,
      'Scan 1',
      onResult: (r) => result = r,
      suggest: () async => 'INVOICE',
    );

    expect(find.byKey(const Key('rename-suggestion')), findsOneWidget);
    expect(find.text('INVOICE'), findsOneWidget);

    await tester.tap(find.byKey(const Key('rename-suggestion')));
    await tester.pump();

    final field = tester.widget<TextField>(
      find.byKey(const Key('rename-field')),
    );
    expect(field.controller!.text, 'INVOICE');

    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(result, 'INVOICE');
  });

  testWidgets('renders no chip when suggest resolves null', (tester) async {
    await pumpDialog(
      tester,
      'Scan 1',
      onResult: (_) {},
      suggest: () async => null,
    );

    expect(find.byKey(const Key('rename-suggestion')), findsNothing);
  });

  testWidgets('renders no chip when suggest resolves empty', (tester) async {
    await pumpDialog(
      tester,
      'Scan 1',
      onResult: (_) {},
      suggest: () async => '   ',
    );

    expect(find.byKey(const Key('rename-suggestion')), findsNothing);
  });

  testWidgets('renders no chip when suggest is null (default)', (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});

    expect(find.byKey(const Key('rename-suggestion')), findsNothing);
  });
}
