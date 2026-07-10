import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/id_scan_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

Widget _host(IdScanScreen screen) => MaterialApp(
  home: Builder(
    builder: (context) => Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => screen)),
          child: const Text('open'),
        ),
      ),
    ),
  ),
);

ScanDependencies _deps(List<List<String>> perCall) => ScanDependencies(
  createDocumentScanner: () => FakeSequentialDocumentScannerService(
    perCall.map((c) => c.map(CapturedImage.new).toList()).toList(),
  ),
);

void main() {
  testWidgets('front then back saves a 2-page id-card document', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(
        IdScanScreen(
          dependencies: _deps(const [
            ['/nonexistent/front.jpg'],
            ['/nonexistent/back.jpg'],
          ]),
          repository: repo,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
    expect(repo.markIdCardCalls.length, 1);
  });

  testWidgets('cancel on front saves nothing', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(
        IdScanScreen(
          dependencies: _deps(const [<String>[]]), // front cancelled
          repository: repo,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 0);
    expect(find.byType(IdScanScreen), findsNothing); // popped
  });

  testWidgets('cancel on back saves nothing', (tester) async {
    final repo = FakeDocumentRepository();
    await tester.pumpWidget(
      _host(
        IdScanScreen(
          dependencies: _deps(const [
            ['/nonexistent/front.jpg'],
            <String>[], // back cancelled
          ]),
          repository: repo,
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(repo.createCalls, 0);
    expect(repo.markIdCardCalls, isEmpty);
  });
}
