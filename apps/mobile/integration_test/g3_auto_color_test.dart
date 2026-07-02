// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_review_screen_is_open_with_a_captured_image.dart';
import './../test/step/i_toggle_the_auto_filter.dart';
import './../test/step/i_tap_accept.dart';
import './../test/step/the_document_is_saved_with_auto_enhancement.dart';
import './../test/step/i_toggle_the_color_filter.dart';
import './../test/step/the_document_is_saved_with_color_enhancement.dart';
import './../test/step/the_document_is_saved_without_enhancement.dart';
import './../test/step/the_auto_enhancer_flattens_the_shadow.dart';
import './../test/step/the_auto_enhancer_preserves_the_photo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''G3 Color and Auto scan enhancement''', () {
    testWidgets(
        '''Auto filter applied — document saved with auto enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iToggleTheAutoFilter(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithAutoEnhancement(tester);
    });
    testWidgets(
        '''Color filter applied — document saved with color enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iToggleTheColorFilter(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithColorEnhancement(tester);
    });
    testWidgets('''No filter — document saved without enhancement''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iTapAccept(tester);
      await theDocumentIsSavedWithoutEnhancement(tester);
    });
    testWidgets('''Auto filter removes the shadow from a shadowed capture''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iToggleTheAutoFilter(tester);
      await iTapAccept(tester);
      await theAutoEnhancerFlattensTheShadow(tester);
    });
    testWidgets(
        '''Auto filter preserves an embedded photo in a shadowed capture''',
        (tester) async {
      await theReviewScreenIsOpenWithACapturedImage(tester);
      await iToggleTheAutoFilter(tester);
      await iTapAccept(tester);
      await theAutoEnhancerPreservesThePhoto(tester);
    });
  });
}
