// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_import_button.dart';
import './../test/step/i_see_the_crop_overlay.dart';
import './../test/step/i_drag_the_crop_handle.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_see_a_saved_document_on_the_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''E1b Every crop handle moves the quad''', () {
    testWidgets('''Dragging all four corners still saves''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheImportButton(tester);
      await iSeeTheCropOverlay(tester);
      await iDragTheCropHandle(tester, 'tl');
      await iDragTheCropHandle(tester, 'tr');
      await iDragTheCropHandle(tester, 'br');
      await iDragTheCropHandle(tester, 'bl');
      await iTapAccept(tester);
      await iSeeASavedDocumentOnTheHome(tester);
    });
    testWidgets('''Dragging all four edge midpoints still saves''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheImportButton(tester);
      await iSeeTheCropOverlay(tester);
      await iDragTheCropHandle(tester, 'top');
      await iDragTheCropHandle(tester, 'right');
      await iDragTheCropHandle(tester, 'bottom');
      await iDragTheCropHandle(tester, 'left');
      await iTapAccept(tester);
      await iSeeASavedDocumentOnTheHome(tester);
    });
  });
}
