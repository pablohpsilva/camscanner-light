// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_review_screen_is_open_with_a_captured_image.dart';
import './../test/step/i_toggle_the_grayscale_filter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/the_document_is_saved_with_grayscale_enhancement.dart';
import './../test/step/the_document_is_saved_without_enhancement.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''G1 grayscale scan enhancement''', () {
    testWidgets(
        '''Grayscale filter applied — document saved with enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iToggleTheGrayscaleFilter(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithGrayscaleEnhancement(tester);
    });
    testWidgets('''No filter — document saved without enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithoutEnhancement(tester);
    });
  });
}
