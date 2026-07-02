import 'package:flutter_test/flutter_test.dart';

import '../support/fake_library.dart';

/// Usage: I see the image export confirmation
///
/// After R2 the page-image export shares the JPG through the ShareChannel
/// instead of showing a "saved" snackbar; the on-device BDD injects a recording
/// FakeShareChannel (via tempLibraryDependencies), so we assert what it received.
Future<void> iSeeTheImageExportConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  final share = lastBddShareChannel;
  expect(share, isNotNull);
  expect(share!.calls, greaterThan(0));
  expect(share.lastFilePaths, isNotNull);
  expect(share.lastFilePaths!.every((p) => p.endsWith('.jpg')), isTrue);
}
