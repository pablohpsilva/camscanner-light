// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_saved_document_with_recognized_text.dart';
import './../test/step/the_app_launches_reading_that_same_storage.dart';
import './../test/step/i_swipe_the_first_document_right.dart';
import './../test/step/i_tap_the_copy_text_swipe_action.dart';
import './../test/step/i_see_the_copy_text_confirmation.dart';
import './../test/step/a_document_was_saved_to_persistent_storage_earlier.dart';
import './../test/step/i_see_the_no_text_to_copy_message.dart';
import './../test/step/i_swipe_the_first_document_left.dart';
import './../test/step/i_tap_the_delete_swipe_action.dart';
import './../test/step/i_confirm_the_delete_dialog.dart';
import './../test/step/the_document_is_gone_from_the_home.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''C5R Home swipe actions against REAL storage''', () {
    testWidgets(
        '''Copying text via swipe copies the document's recognized text''',
        (tester) async {
      await aSavedDocumentWithRecognizedText(tester, 'HELLO WORLD');
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSwipeTheFirstDocumentRight(tester);
      await iTapTheCopyTextSwipeAction(tester);
      await iSeeTheCopyTextConfirmation(tester);
    });
    testWidgets(
        '''Copying from a document with no text says so instead of copying''',
        (tester) async {
      await aDocumentWasSavedToPersistentStorageEarlier(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSwipeTheFirstDocumentRight(tester);
      await iTapTheCopyTextSwipeAction(tester);
      await iSeeTheNoTextToCopyMessage(tester);
    });
    testWidgets('''Deleting via swipe removes the document from real storage''',
        (tester) async {
      await aDocumentWasSavedToPersistentStorageEarlier(tester);
      await theAppLaunchesReadingThatSameStorage(tester);
      await iSwipeTheFirstDocumentLeft(tester);
      await iTapTheDeleteSwipeAction(tester);
      await iConfirmTheDeleteDialog(tester);
      await theDocumentIsGoneFromTheHome(tester);
    });
  });
}
