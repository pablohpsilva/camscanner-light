// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_tap_the_shutter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_open_the_rename_menu_for_the_first_document.dart';
import './../test/step/i_rename_the_document_to.dart';
import './../test/step/i_see_text.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Rename a document''', () {
    testWidgets('''Rename a document from the library list''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iOpenTheRenameMenuForTheFirstDocument(tester);
      await iRenameTheDocumentTo(tester, 'Field Notes');
      await iSeeText(tester, 'Field Notes');
    });
  });
}
