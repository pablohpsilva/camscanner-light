// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../step/the_library_has_a_document_scan1_whose_page_has_ocr_text_suggesting_invoice.dart';
import './../../step/the_library_organize_screen_is_showing.dart';
import './../../step/i_open_the_rename_menu_for_the_first_document.dart';
import '../../step/the_rename_dialog_shows_a_suggestion_invoice.dart';
import './../../step/i_tap_the_rename_suggestion.dart';
import '../../step/the_rename_field_shows_invoice.dart';

void main() {
  group('''Suggested title from OCR text''', () {
    testWidgets('''Opening rename shows a suggestion that fills the name''',
        (tester) async {
      await theLibraryHasADocumentScan1WhosePageHasOcrTextSuggestingInvoice(
          tester);
      await theLibraryOrganizeScreenIsShowing(tester);
      await iOpenTheRenameMenuForTheFirstDocument(tester);
      await theRenameDialogShowsASuggestionInvoice(tester);
      await iTapTheRenameSuggestion(tester);
      await theRenameFieldShowsInvoice(tester);
    });
  });
}
