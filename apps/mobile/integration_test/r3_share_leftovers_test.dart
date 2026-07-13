// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_with_fax_enabled_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_documents_menu.dart';
import './../test/step/i_tap_the_fax_action.dart';
import './../test/step/i_see_the_message.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Share leftovers surface as not-yet-available''', () {
    testWidgets('''Fax on a document is not available yet''', (tester) async {
      await aDocumentWasSavedToPersistentStorageEarlier(tester);
      await theAppLaunchesWithFaxEnabledReadingThatSameStorage(tester);
      await iOpenTheFirstDocumentsMenu(tester);
      await iTapTheFaxAction(tester);
      await iSeeTheMessage(tester, 'Fax isn\'t available yet');
    });
  });
}
