// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_with_the_print_feature_disabled.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_see_the_page_viewer.dart';
import './../test/step/i_open_the_share_menu.dart';
import './../test/step/i_do_not_see_the_print_action.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Build-time feature flags hide disabled actions''', () {
    testWidgets(
        '''A build with the print feature disabled hides the Print action''',
        (tester) async {
      await aDocumentWithARealPageImageWasSavedToPersistentStorageEarlier(
          tester);
      await theAppLaunchesWithThePrintFeatureDisabled(tester);
      await iOpenTheFirstDocument(tester);
      await iSeeThePageViewer(tester);
      await iOpenTheShareMenu(tester);
      await iDoNotSeeThePrintAction(tester);
    });
  });
}
