// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/two_documents_with_real_page_images_were_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_merge_the_other_document.dart';
import './../test/step/i_see_two_page_thumbnails.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Merge documents''', () {
    testWidgets('''Merge another document into the open one''', (tester) async {
      await twoDocumentsWithRealPageImagesWereSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iMergeTheOtherDocument(tester);
      await iSeeTwoPageThumbnails(tester);
    });
  });
}
