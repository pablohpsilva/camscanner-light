// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_swipeable_document_list.dart';
import './../test/step/i_swipe_the_first_document_right.dart';
import './../test/step/i_see_the_copy_text_swipe_action.dart';
import './../test/step/i_see_the_protect_swipe_action.dart';
import './../test/step/i_tap_the_copy_text_swipe_action.dart';
import './../test/step/the_copy_text_action_fired.dart';
import './../test/step/i_swipe_the_first_document_left.dart';
import './../test/step/i_tap_the_delete_swipe_action.dart';
import './../test/step/i_confirm_the_delete_dialog.dart';
import './../test/step/the_delete_action_fired.dart';
import './../test/step/i_cancel_the_delete_dialog.dart';
import './../test/step/the_delete_action_did_not_fire.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Document list swipe actions''', () {
    testWidgets('''Swipe right reveals the quick actions''', (tester) async {
      await aSwipeableDocumentList(tester);
      await iSwipeTheFirstDocumentRight(tester);
      await iSeeTheCopyTextSwipeAction(tester);
      await iSeeTheProtectSwipeAction(tester);
    });
    testWidgets('''Copy text via swipe right''', (tester) async {
      await aSwipeableDocumentList(tester);
      await iSwipeTheFirstDocumentRight(tester);
      await iTapTheCopyTextSwipeAction(tester);
      await theCopyTextActionFired(tester);
    });
    testWidgets('''Swipe left then confirm deletes''', (tester) async {
      await aSwipeableDocumentList(tester);
      await iSwipeTheFirstDocumentLeft(tester);
      await iTapTheDeleteSwipeAction(tester);
      await iConfirmTheDeleteDialog(tester);
      await theDeleteActionFired(tester);
    });
    testWidgets('''Swipe left then cancel does not delete''', (tester) async {
      await aSwipeableDocumentList(tester);
      await iSwipeTheFirstDocumentLeft(tester);
      await iTapTheDeleteSwipeAction(tester);
      await iCancelTheDeleteDialog(tester);
      await theDeleteActionDidNotFire(tester);
    });
  });
}
