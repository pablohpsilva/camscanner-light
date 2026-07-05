// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_saved_document_named_with_page_text.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_search_for.dart';
import './../test/step/i_see_text.dart';
import './../test/step/i_see_the_no_matches_message.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Search the library by content''', () {
    testWidgets('''Find a document by the text inside it''', (tester) async {
      await aSavedDocumentNamedWithPageText(tester, 'Untitled', 'INVOICE 2026');
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSearchFor(tester, 'invoice');
      await iSeeText(tester, 'Untitled');
      await iSearchFor(tester, 'zzz');
      await iSeeTheNoMatchesMessage(tester);
    });
  });
}
