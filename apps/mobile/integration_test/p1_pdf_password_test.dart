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
import './../test/step/i_protect_with_a_password.dart';
import './../test/step/i_see_the_protected_pdf_confirmation.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Password-protect a PDF''', () {
    testWidgets('''Export a password-protected PDF''', (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iTapDone(tester);
      await iOpenTheFirstDocument(tester);
      await iProtectWithAPassword(tester);
      await iSeeTheProtectedPdfConfirmation(tester);
    });
  });
}
