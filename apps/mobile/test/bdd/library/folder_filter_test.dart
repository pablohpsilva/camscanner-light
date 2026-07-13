// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../step/the_library_has_a_document_invoice_in_folder_work.dart';
import '../../step/the_library_has_a_document_recipe_with_no_folder.dart';
import '../../step/the_library_home_screen_is_showing.dart';
import './../../step/i_tap_the_folder_chip_work.dart';
import './../../step/i_see_the_document_invoice.dart';
import './../../step/i_do_not_see_the_document_recipe.dart';

void main() {
  group('''Folder filtering''', () {
    testWidgets('''Filter documents by folder''', (tester) async {
      await theLibraryHasADocumentInvoiceInFolderWork(tester);
      await theLibraryHasADocumentRecipeWithNoFolder(tester);
      await theLibraryHomeScreenIsShowing(tester);
      await iTapTheFolderChipWork(tester);
      await iSeeTheDocumentInvoice(tester);
      await iDoNotSeeTheDocumentRecipe(tester);
    });
  });
}
