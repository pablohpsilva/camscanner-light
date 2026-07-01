// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/the_page_viewer_is_open_with2_pages.dart';
import './../test/step/the_second_page_thumbnail_is_dragged_to_the_first_position.dart';
import './../test/step/the_first_visible_page_is_position2.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''H3 Page reorder''', () {
    testWidgets(
        '''Dragging the second thumbnail to the first position swaps the order''',
        (tester) async {
      await thePageViewerIsOpenWith2Pages(tester);
      await theSecondPageThumbnailIsDraggedToTheFirstPosition(tester);
      await theFirstVisiblePageIsPosition2(tester);
    });
  });
}
