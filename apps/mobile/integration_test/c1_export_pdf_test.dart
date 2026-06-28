// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_tap_the_shutter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_export_the_open_document_to_pdf.dart';
import './../test/step/the_pdf_is_saved.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Export a document to PDF''', () {
    testWidgets('''Capture, save, then export the document to PDF''',
        (tester) async {
      await theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(tester);
      await iTapTheScanButton(tester);
      await iTapTheShutter(tester);
      await iTapAccept(tester);
      await iOpenTheFirstDocument(tester);
      await iExportTheOpenDocumentToPdf(tester);
      await thePdfIsSaved(tester);
    });
  });
}
