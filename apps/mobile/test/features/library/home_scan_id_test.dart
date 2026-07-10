import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/scan/id_scan_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  testWidgets('tapping Scan ID opens the ID scan screen', (tester) async {
    // Inject a never-completing scanner so IdScanScreen stays visible.
    // pumpAndSettle must NOT be used after tapping — IdScanScreen shows a
    // CircularProgressIndicator which keeps scheduling animation frames.
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: ScanDependencies(
            createDocumentScanner: HangingDocumentScannerService.new,
          ),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // initial library load (no scanner involved)
    await tester.tap(find.byKey(const Key('home-scan-id')));
    await tester
        .pump(); // dispatch tap, push IdScanScreen, post-frame _run() starts
    await tester.pump(); // settle pending microtasks; _run() awaits scanner
    expect(find.byType(IdScanScreen), findsOneWidget);
  });
}
