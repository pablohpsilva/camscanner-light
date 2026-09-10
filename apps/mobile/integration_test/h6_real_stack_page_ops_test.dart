// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with2_real_page_images_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_delete_the_current_page.dart';
import './../test/step/the_document_has1_page.dart';
import './../test/step/i_go_back_to_home_from_the_page_viewer.dart';
import './../test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart';
import './../test/step/the_first_visible_page_is_position2.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H6 Page operations against REAL storage''', () {
    testWidgets('''Deleting a page updates the real database''',
        (tester) async {
      await aDocumentWith2RealPageImagesWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iDeleteTheCurrentPage(tester);
      await theDocumentHas1Page(tester);
    });
    testWidgets('''A deleted page stays deleted after a relaunch''',
        (tester) async {
      await aDocumentWith2RealPageImagesWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iDeleteTheCurrentPage(tester);
      await iGoBackToHomeFromThePageViewer(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await theDocumentHas1Page(tester);
    });
    testWidgets('''Reordering pages persists to the real database''',
        (tester) async {
      await aDocumentWith2RealPageImagesWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await theSecondPageThumbnailIsDraggedToTheFirstPosition(tester);
      await theFirstVisiblePageIsPosition2(tester);
    });
  });
}
