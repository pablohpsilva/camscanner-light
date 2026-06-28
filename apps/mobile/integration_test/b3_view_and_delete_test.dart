// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_delete_the_open_document.dart';
import './../test/step/the_document_is_gone_from_the_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''View and delete a document''', () {
    testWidgets('''Open a saved document, view its page, then delete it''',
        (tester) async {
      await aDocumentWasSavedToPersistentStorageEarlier(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iOpenTheFirstDocument(tester);
      await iDeleteTheOpenDocument(tester);
      await theDocumentIsGoneFromTheHome(tester);
    });
  });
}
