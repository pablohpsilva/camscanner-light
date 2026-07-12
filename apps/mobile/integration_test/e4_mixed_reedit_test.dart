// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_see_the_page_viewer.dart';
import './../test/step/i_rotate_the_page.dart';
import './../test/step/i_tap_the_edit_crop_button.dart';
import './../test/step/i_see_the_crop_overlay.dart';
import './../test/step/i_drag_the_top_left_crop_corner.dart';
import './../test/step/i_tap_accept_on_the_viewer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Mixed re-edit of a page''', () {
    testWidgets('''Rotate and crop repeatedly without error''', (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
        tester,
      );
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iSeeThePageViewer(tester);
      await iRotateThePage(tester);
      await iTapTheEditCropButton(tester);
      await iSeeTheCropOverlay(tester);
      await iDragTheTopLeftCropCorner(tester);
      await iTapAcceptOnTheViewer(tester);
      await iSeeThePageViewer(tester);
      await iRotateThePage(tester);
      await iTapTheEditCropButton(tester);
      await iSeeTheCropOverlay(tester);
      await iDragTheTopLeftCropCorner(tester);
      await iTapAcceptOnTheViewer(tester);
      await iSeeThePageViewer(tester);
    });
  });
}
