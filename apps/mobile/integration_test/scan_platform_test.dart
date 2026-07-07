// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/step/the_app_is_launched_with_a_fake_scanner_returning2_pages.dart';
import '../test/step/i_open_the_scanner.dart';
import './../test/step/i_tap_accept.dart';
import '../test/step/a_document_with2_pages_is_saved.dart';
import '../test/step/the_app_is_launched_with_a_fake_scanner_returning0_pages.dart';
import '../test/step/no_document_is_saved.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Platform document scanner''', () {
    testWidgets('''Scanning 2 pages saves a document''', (tester) async {
      await theAppIsLaunchedWithAFakeScannerReturning2Pages(tester);
      await iOpenTheScanner(tester);
      await iTapAccept(tester);
      await aDocumentWith2PagesIsSaved(tester);
    });
    testWidgets('''Cancelling the scanner returns to the home''',
        (tester) async {
      await theAppIsLaunchedWithAFakeScannerReturning0Pages(tester);
      await iOpenTheScanner(tester);
      await noDocumentIsSaved(tester);
    });
  });
}
