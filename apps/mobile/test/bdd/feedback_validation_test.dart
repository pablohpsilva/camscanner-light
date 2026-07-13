// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../step/the_feedback_screen_backed_by_a_service_that_rejects_as_invalid.dart';
import './../step/i_enter_a_feedback_message.dart';
import './../step/i_tap_send_feedback.dart';
import './../step/i_see_the_message_please_check_your_message_and_try_again.dart';
import './../step/i_tap_the_feedback_back_button.dart';
import './../step/the_feedback_screen_is_dismissed.dart';

void main() {
  group('''Feedback submission result messaging''', () {
    testWidgets(
      '''Server rejects the feedback as invalid and the user goes back''',
      (tester) async {
        await theFeedbackScreenBackedByAServiceThatRejectsAsInvalid(tester);
        await iEnterAFeedbackMessage(tester);
        await iTapSendFeedback(tester);
        await iSeeTheMessagePleaseCheckYourMessageAndTryAgain(tester);
        await iTapTheFeedbackBackButton(tester);
        await theFeedbackScreenIsDismissed(tester);
      },
    );
  });
}
