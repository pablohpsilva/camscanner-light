import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: I see the all images export confirmation
///
/// After R2 "export all" shares one JPG per page through the ShareChannel; the
/// on-device BDD injects a recording FakeShareChannel, so we assert every shared
/// path is a JPG.
Future<void> iSeeTheAllImagesExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths, isNotNull);
  expect(share.lastFilePaths!.isNotEmpty, isTrue);
  expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
}
