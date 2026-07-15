// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../step/the_feedback_screen_backed_by_a_stalled_service.dart';
import './../step/i_enter_a_feedback_message.dart';
import './../step/i_tap_send_feedback.dart';
import '../step/i_see_the_message_check_your_connection_and_try_again.dart';
import './../step/the_feedback_submit_control_is_enabled_again.dart';

void main() {
  group('''Feedback submission survives a stalled network''', () {
    testWidgets(
        '''A stalled submit surfaces the offline message and re-enables submit''',
        (tester) async {
      await theFeedbackScreenBackedByAStalledService(tester);
      await iEnterAFeedbackMessage(tester);
      await iTapSendFeedback(tester);
      await iSeeTheMessageCheckYourConnectionAndTryAgain(tester);
      await theFeedbackSubmitControlIsEnabledAgain(tester);
    });
  });
}
