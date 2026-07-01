// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_camera_screen_is_open.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/the_camera_screen_shows_the_done_button.dart';
import './../test/step/i_capture_and_accept_the_second_page.dart';
import './../test/step/i_tap_done.dart';
import '../test/step/the_document_has2_pages.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H1 Add multiple pages to a document''', () {
    testWidgets('''Accepting first page keeps camera open''', (tester) async {
      await theCameraScreenIsOpen(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await theCameraScreenShowsTheDoneButton(tester);
    });
    testWidgets('''Two pages are saved to the same document''', (tester) async {
      await theCameraScreenIsOpen(tester);
      await iCaptureAndAcceptTheFirstPage(tester);
      await iCaptureAndAcceptTheSecondPage(tester);
      await iTapDone(tester);
      await theDocumentHas2Pages(tester);
    });
  });
}
