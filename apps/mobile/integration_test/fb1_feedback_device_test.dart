// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_feedback_screen_backed_by_a_stalled_service.dart';
import './../test/step/i_enter_a_feedback_message.dart';
import './../test/step/i_tap_send_feedback.dart';
import './../test/step/i_see_the_message_check_your_connection_and_try_again.dart';
import './../test/step/the_feedback_submit_control_is_enabled_again.dart';
import './../test/step/the_feedback_screen_backed_by_a_service_that_rejects_as_invalid.dart';
import './../test/step/i_see_the_message_please_check_your_message_and_try_again.dart';
import './../test/step/i_tap_the_feedback_back_button.dart';
import './../test/step/the_feedback_screen_is_dismissed.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''FB1 Feedback submission on a real device''', () {
    testWidgets(
        '''A stalled submit surfaces the offline message and re-enables submit''',
        (tester) async {
      await theFeedbackScreenBackedByAStalledService(tester);
      await iEnterAFeedbackMessage(tester);
      await iTapSendFeedback(tester);
      await iSeeTheMessageCheckYourConnectionAndTryAgain(tester);
      await theFeedbackSubmitControlIsEnabledAgain(tester);
    });
    testWidgets(
        '''Server rejects the feedback as invalid and the user goes back''',
        (tester) async {
      await theFeedbackScreenBackedByAServiceThatRejectsAsInvalid(tester);
      await iEnterAFeedbackMessage(tester);
      await iTapSendFeedback(tester);
      await iSeeTheMessagePleaseCheckYourMessageAndTryAgain(tester);
      await iTapTheFeedbackBackButton(tester);
      await theFeedbackScreenIsDismissed(tester);
    });
  });
}
