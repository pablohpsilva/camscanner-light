// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/step/a_document_with3_real_page_images_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_export_the_open_document_to_pdf.dart';
import './../test/step/the_pdf_preview_opens.dart';
import './../test/step/the_exported_pdf_has3_pages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H5 Multi-page PDF export''', () {
    testWidgets('''Exporting a three-page document produces a three-page PDF''',
        (tester) async {
      await aDocumentWith3RealPageImagesWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iExportTheOpenDocumentToPdf(tester);
      await thePdfPreviewOpens(tester);
      await theExportedPdfHas3Pages(tester);
    });
  });
}
