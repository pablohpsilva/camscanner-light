// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_page_viewer_is_open_with2_pages.dart';
import './../test/step/i_see_the_page_thumbnail_strip.dart';
import './../test/step/i_tap_the_second_page_thumbnail.dart';
import './../test/step/the_viewer_has_navigated_to_page2.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H2 Page thumbnail strip''', () {
    testWidgets('''Thumbnail strip is visible on a multi-page document''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await iSeeThePageThumbnailStrip(tester);
    });
    testWidgets('''Tapping a thumbnail navigates to that page''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await iTapTheSecondPageThumbnail(tester);
      await theViewerHasNavigatedToPage2(tester);
    });
  });
}
