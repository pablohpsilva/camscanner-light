// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_tap_the_sort_chip.dart';
import './../test/step/i_see_the_sort_chip_is_active.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Sort the library''', () {
    testWidgets('''Switch the library sort to name''', (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iTapTheSortChip(tester, 'name');
      await iSeeTheSortChipIsActive(tester, 'name');
    });
  });
}
