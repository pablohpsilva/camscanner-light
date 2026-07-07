// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_saved_document_report_with_page1_text_acme_corporation_and_page3_text_final_invoice.dart';
import './../test/step/a_saved_document_decoy_with_page1_text_acme_only_nothing_else.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_search_and_type_acme_invoice.dart';
import './../test/step/i_see_the_document_report.dart';
import './../test/step/i_do_not_see_the_document_decoy.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Multi-word content search ranks and spans pages''', () {
    testWidgets(
        '''A query whose words are on different pages still finds the document''',
        (tester) async {
      await aSavedDocumentReportWithPage1TextAcmeCorporationAndPage3TextFinalInvoice(
          tester);
      await aSavedDocumentDecoyWithPage1TextAcmeOnlyNothingElse(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenSearchAndTypeAcmeInvoice(tester);
      await iSeeTheDocumentReport(tester);
      await iDoNotSeeTheDocumentDecoy(tester);
    });
  });
}
