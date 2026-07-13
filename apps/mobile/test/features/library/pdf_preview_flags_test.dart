import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/pdf_preview_screen.dart';

Future<void> _pump(WidgetTester tester, {FeatureFlags? features}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: PdfPreviewScreen(
        pdfPath: '/x.pdf',
        name: 'x',
        opener: (_) async => throw Exception('no native in host'),
        features: features ?? const FeatureFlags(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('pdf-preview-share')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('default flags hide fax but show share-link', (tester) async {
    await _pump(tester);
    expect(find.byKey(const Key('share-menu-fax')), findsNothing);
    expect(find.byKey(const Key('share-menu-share-link')), findsOneWidget);
  });

  testWidgets('fax: true shows the fax item', (tester) async {
    await _pump(tester, features: const FeatureFlags(fax: true));
    expect(find.byKey(const Key('share-menu-fax')), findsOneWidget);
  });
}
