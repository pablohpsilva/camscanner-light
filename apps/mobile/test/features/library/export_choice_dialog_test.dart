import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/export_choice_dialog.dart';

void main() {
  // Shows the dialog, taps [choice] (or the barrier when null), and returns the
  // captured result. The dialog future is awaited inside the button callback so
  // the test never flattens it prematurely.
  Future<MultiExportChoice?> openAndChoose(
      WidgetTester tester, Key? choice) async {
    MultiExportChoice? captured;
    var completed = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              captured = await showExportChoiceDialog(context);
              completed = true;
            },
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    if (choice != null) {
      await tester.tap(find.byKey(choice));
    } else {
      await tester.tapAt(const Offset(10, 10)); // tap the barrier
    }
    await tester.pumpAndSettle();
    expect(completed, isTrue);
    return captured;
  }

  testWidgets('choosing Merge returns MultiExportChoice.merged', (tester) async {
    expect(await openAndChoose(tester, const Key('export-choice-merged')),
        MultiExportChoice.merged);
  });

  testWidgets('choosing Separate returns MultiExportChoice.separateZip',
      (tester) async {
    expect(await openAndChoose(tester, const Key('export-choice-zip')),
        MultiExportChoice.separateZip);
  });

  testWidgets('dismissing returns null', (tester) async {
    expect(await openAndChoose(tester, null), isNull);
  });
}
