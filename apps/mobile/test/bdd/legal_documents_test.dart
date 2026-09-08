// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../step/the_app_is_launched_with_empty_storage_and_mocked_preferences.dart';
import './../step/i_open_settings_from_home.dart';
import './../step/i_open_the_terms_of_service.dart';
import './../step/the_document_disclaims_all_warranties.dart';
import './../step/the_document_says_i_am_responsible_for_what_i_scan.dart';
import './../step/i_open_the_privacy_policy.dart';
import './../step/the_document_warns_that_feedback_is_public.dart';
import './../step/i_open_the_faq.dart';
import './../step/i_expand_the_first_question.dart';
import './../step/the_answer_is_shown.dart';
import './../step/i_choose_the_spanish_language.dart';
import './../step/the_english_prevails_notice_is_shown.dart';
import './../step/i_tap_the_privacy_policy_link.dart';

void main() {
  group('''Legal documents''', () {
    testWidgets(
        '''The terms disclaim liability and place responsibility on the user''',
        (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iOpenTheTermsOfService(tester);
      await theDocumentDisclaimsAllWarranties(tester);
      await theDocumentSaysIAmResponsibleForWhatIScan(tester);
    });
    testWidgets('''The privacy policy warns that feedback is public''',
        (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iOpenThePrivacyPolicy(tester);
      await theDocumentWarnsThatFeedbackIsPublic(tester);
    });
    testWidgets('''FAQ answers are hidden until a question is tapped''',
        (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iOpenTheFaq(tester);
      await iExpandTheFirstQuestion(tester);
      await theAnswerIsShown(tester);
    });
    testWidgets('''A translated document says the English version prevails''',
        (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iChooseTheSpanishLanguage(tester);
      await iOpenTheTermsOfService(tester);
      await theEnglishPrevailsNoticeIsShown(tester);
    });
    testWidgets(
        '''Tapping a sibling document link opens that document in-app''',
        (tester) async {
      await theAppIsLaunchedWithEmptyStorageAndMockedPreferences(tester);
      await iOpenSettingsFromHome(tester);
      await iOpenTheTermsOfService(tester);
      await iTapThePrivacyPolicyLink(tester);
      await theDocumentWarnsThatFeedbackIsPublic(tester);
    });
  });
}
