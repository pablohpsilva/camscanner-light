// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_rename_menu_for_the_first_document.dart';
import './../test/step/i_rename_the_document_to.dart';
import './../test/step/i_see_text.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Rename a document''', () {
    testWidgets('''Rename a document from the library list''', (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheRenameMenuForTheFirstDocument(tester);
      await iRenameTheDocumentTo(tester, 'Field Notes');
      await iSeeText(tester, 'Field Notes');
    });
  });
}
