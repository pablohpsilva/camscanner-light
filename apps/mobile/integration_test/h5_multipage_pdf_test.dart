// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/i_capture_and_accept_the_second_page.dart';
import './../test/step/i_capture_and_accept_the_third_page.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_export_the_open_document_to_pdf.dart';
import './../test/step/the_pdf_preview_opens.dart';
import './../test/step/the_exported_pdf_has3_pages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H5 Multi-page PDF export''', () {
    testWidgets('''Exporting a three-page document produces a three-page PDF''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iCaptureAndAcceptTheSecondPage(tester);
      await iCaptureAndAcceptTheThirdPage(tester);
      await iTapDone(tester);
      await iOpenTheFirstDocument(tester);
      await iExportTheOpenDocumentToPdf(tester);
      await thePdfPreviewOpens(tester);
      await theExportedPdfHas3Pages(tester);
    });
  });
}
