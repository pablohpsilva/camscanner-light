// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_export_the_page_as_an_image.dart';
import './../test/step/i_see_the_image_export_confirmation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''I1 Export page as image''', () {
    testWidgets('''Exporting the open page saves it as an image''',
        (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iExportThePageAsAnImage(tester);
      await iSeeTheImageExportConfirmation(tester);
    });
  });
}
