import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: a zip is handed to the share sheet
Future<void> aZipIsHandedToTheShareSheet(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths!.single, endsWith('.zip'));
  expect(share.lastMimeType, 'application/zip');
}
