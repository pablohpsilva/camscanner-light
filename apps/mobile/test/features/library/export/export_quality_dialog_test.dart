import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/export/export_quality_dialog.dart';

Future<ExportQuality?> _open(WidgetTester tester) async {
  ExportQuality? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async =>
                result = await showExportQualityDialog(context),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result; // still null until the dialog resolves
}

void main() {
  testWidgets('shows the four options', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('export-quality-dialog')), findsOneWidget);
    for (final q in ExportQuality.values) {
      expect(find.byKey(Key('export-quality-${q.name}')), findsOneWidget);
    }
  });

  testWidgets('tapping an option dismisses the dialog', (tester) async {
    await _open(tester);
    await tester.tap(find.byKey(const Key('export-quality-medium')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-quality-dialog')), findsNothing);
  });

  testWidgets('returns the chosen quality value', (tester) async {
    ExportQuality? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  picked = await showExportQualityDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-low')));
    await tester.pumpAndSettle();
    expect(picked, ExportQuality.low);
  });

  testWidgets('cancel returns null', (tester) async {
    ExportQuality? picked = ExportQuality.high;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  picked = await showExportQualityDialog(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-quality-cancel')));
    await tester.pumpAndSettle();
    expect(picked, isNull);
  });
}
