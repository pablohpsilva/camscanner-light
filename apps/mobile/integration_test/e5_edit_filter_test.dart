// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_see_the_page_viewer.dart';
import './../test/step/i_tap_the_filter_button.dart';
import './../test/step/i_tap_the_grayscale_filter_tile.dart';
import './../test/step/i_tap_save_on_the_filter_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Change a saved page's filter''', () {
    testWidgets('''Apply a grayscale filter to a saved page without error''',
        (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iSeeThePageViewer(tester);
      await iTapTheFilterButton(tester);
      await iTapTheGrayscaleFilterTile(tester);
      await iTapSaveOnTheFilterScreen(tester);
      await iSeeThePageViewer(tester);
    });
  });
}
