// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import './../test/step/a_saved_document_with_recognized_text.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_open_the_text_view.dart';
import './../test/step/i_see_text.dart';
import './../test/step/i_copy_the_recognized_text.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('''View and copy recognized text''', () {
    testWidgets('''Open a page's recognized text and copy it''',
        (tester) async {
      await aSavedDocumentWithRecognizedText(tester, 'HELLO WORLD');
      await iOpenTheFirstDocument(tester);
      await iOpenTheTextView(tester);
      await iSeeText(tester, 'HELLO WORLD');
      await iCopyTheRecognizedText(tester);
      await iSeeText(tester, 'Copied');
    });
  });
}
