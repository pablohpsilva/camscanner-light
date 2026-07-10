// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_app_is_launched_with_a_fake_id_camera_returning_a_front_and_a_back.dart';
import './../test/step/i_open_the_id_scanner.dart';
import './../test/step/i_accept_the_captured_front.dart';
import './../test/step/i_accept_the_captured_back.dart';
import './../test/step/an_id_card_document_with2_pages_is_saved.dart';
import './../test/step/i_retake_the_front.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''Scan an ID card''', () {
    testWidgets('''Accepting front and back saves a 2-page ID document''', (
      tester,
    ) async {
      await theAppIsLaunchedWithAFakeIdCameraReturningAFrontAndABack(tester);
      await iOpenTheIdScanner(tester);
      await iAcceptTheCapturedFront(tester);
      await iAcceptTheCapturedBack(tester);
      await anIdCardDocumentWith2PagesIsSaved(tester);
    });
    testWidgets(
      '''Retaking the front then accepting still saves a 2-page ID document''',
      (tester) async {
        await theAppIsLaunchedWithAFakeIdCameraReturningAFrontAndABack(tester);
        await iOpenTheIdScanner(tester);
        await iRetakeTheFront(tester);
        await iAcceptTheCapturedFront(tester);
        await iAcceptTheCapturedBack(tester);
        await anIdCardDocumentWith2PagesIsSaved(tester);
      },
    );
  });
}
