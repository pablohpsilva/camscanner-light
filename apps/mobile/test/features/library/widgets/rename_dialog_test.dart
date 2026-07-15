import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/rename_dialog.dart';

import '../../../support/localized_app.dart';

void main() {
  // Pump a trivial host with a button that opens the dialog and stores the
  // result, so each test can assert what showRenameDialog returned.
  Future<void> pumpDialog(
    WidgetTester tester,
    String current, {
    required void Function(String?) onResult,
  }) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  final r = await showRenameDialog(context, current);
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

  testWidgets('pre-fills and fully selects the current name', (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    final field = tester.widget<TextField>(
      find.byKey(const Key('rename-field')),
    );
    expect(field.controller!.text, 'Scan 1');
    expect(
      field.controller!.selection,
      const TextSelection(baseOffset: 0, extentOffset: 6),
    );
  });

  testWidgets('Save is disabled when the field is empty/whitespace', (
    tester,
  ) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    await tester.enterText(find.byKey(const Key('rename-field')), '   ');
    await tester.pump();
    final save = tester.widget<TextButton>(
      find.byKey(const Key('rename-save')),
    );
    expect(save.onPressed, isNull);
  });

  testWidgets('returns the trimmed new name on Save', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.enterText(find.byKey(const Key('rename-field')), '  Taxes  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(result, 'Taxes');
  });

  testWidgets('returns null on Cancel', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.enterText(find.byKey(const Key('rename-field')), 'Changed');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('returns null when the name is unchanged', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.tap(
      find.byKey(const Key('rename-save')),
    ); // Save without editing
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('caps the field at 100 characters', (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    final field = tester.widget<TextField>(
      find.byKey(const Key('rename-field')),
    );
    expect(field.maxLength, 100);
  });
}
