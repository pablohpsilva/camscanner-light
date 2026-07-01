// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_import_a_photo_from_the_gallery.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_see_a_saved_document_on_the_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''I2 Gallery import''', () {
    testWidgets('''Importing a photo from the gallery saves it as a document''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iImportAPhotoFromTheGallery(tester);
      await iTapAccept(tester);
      await iTapDone(tester);
      await iSeeASavedDocumentOnTheHome(tester);
    });
  });
}
