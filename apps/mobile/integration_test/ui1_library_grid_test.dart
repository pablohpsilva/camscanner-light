// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_switch_to_grid_view.dart';
import './../test/step/i_see_the_document_in_grid.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Library grid view''', () {
    testWidgets('''Switch the library to grid and see a saved document''',
        (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSwitchToGridView(tester);
      await iSeeTheDocumentInGrid(tester);
    });
  });
}
