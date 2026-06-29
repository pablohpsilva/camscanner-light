// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_tap_the_shutter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_see_a_saved_document_on_the_home.dart';
import './../test/step/saving_documents_fails.dart';
import './../test/step/i_see_the_save_error.dart';
import './../test/step/i_see_the_capture_review_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Save a captured document''', () {
    testWidgets('''Accepting a capture saves it and shows it on the home''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iSeeASavedDocumentOnTheHome(tester);
    });
    testWidgets('''A failed save keeps me on the review screen''',
        (tester) async {
      await savingDocumentsFails(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iSeeTheSaveError(tester);
      await iSeeTheCaptureReviewScreen(tester);
    });
  });
}
