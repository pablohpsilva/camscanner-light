// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_import_button.dart';
import './../test/step/i_see_the_crop_overlay.dart';
import './../test/step/i_drag_the_top_left_crop_corner.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_see_a_saved_document_on_the_home.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_see_the_page_viewer.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Perspective flatten''', () {
    testWidgets(
        '''Flat image is shown in the page viewer after import with adjusted corners''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheImportButton(tester);
      await iSeeTheCropOverlay(tester);
      await iDragTheTopLeftCropCorner(tester);
      await iTapAccept(tester);
      await iSeeASavedDocumentOnTheHome(tester);
      await iOpenTheFirstDocument(tester);
      await iSeeThePageViewer(tester);
    });
  });
}
