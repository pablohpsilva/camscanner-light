// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_merge_the_other_document.dart';
import './../test/step/i_see_two_page_thumbnails.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Merge documents''', () {
    testWidgets('''Merge another document into the open one''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iTapDone(tester);
      await iTapTheScanButton(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iTapDone(tester);
      await iOpenTheFirstDocument(tester);
      await iMergeTheOtherDocument(tester);
      await iSeeTwoPageThumbnails(tester);
    });
  });
}
