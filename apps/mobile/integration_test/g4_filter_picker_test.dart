// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_review_screen_is_open_with_a_captured_image.dart';
import './../test/step/i_see_the_filter_picker_strip.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/the_document_is_saved_with_auto_enhancement.dart';
import './../test/step/i_tap_the_grayscale_filter_tile.dart';
import './../test/step/the_document_is_saved_with_grayscale_enhancement.dart';
import './../test/step/i_tap_the_original_filter_tile.dart';
import './../test/step/the_document_is_saved_without_enhancement.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''G4 Filter picker strip''', () {
    testWidgets('''Filter picker strip is visible on the review screen''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iSeeTheFilterPickerStrip(tester);
    });
    testWidgets('''Auto filter is selected by default''', (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithAutoEnhancement(tester);
    });
    testWidgets('''Tapping Grayscale tile saves with GrayscaleEnhancer''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iTapTheGrayscaleFilterTile(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithGrayscaleEnhancement(tester);
    });
    testWidgets('''Tapping Original tile saves without enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iTapTheOriginalFilterTile(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithoutEnhancement(tester);
    });
  });
}
