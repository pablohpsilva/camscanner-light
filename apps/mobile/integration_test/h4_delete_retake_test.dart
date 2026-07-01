// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_page_viewer_is_open_with2_pages.dart';
import './../test/step/i_delete_the_current_page.dart';
import './../test/step/the_document_has1_page.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H4 Delete page''', () {
    testWidgets('''Deleting one page of a two-page document leaves one page''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await iDeleteTheCurrentPage(tester);
      await theDocumentHas1Page(tester);
    });
  });
}
