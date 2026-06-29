// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_document_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_see_a_saved_document_on_the_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Documents persist across an app restart''', () {
    testWidgets('''A document saved earlier is listed after a fresh launch''',
        (tester) async {
      await aDocumentWasSavedToPersistentStorageEarlier(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSeeASavedDocumentOnTheHome(tester);
    });
  });
}
