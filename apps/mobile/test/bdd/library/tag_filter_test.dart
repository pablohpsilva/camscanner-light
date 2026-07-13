// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../../step/the_library_has_a_document_invoice_tagged_work.dart';
import './../../step/the_library_has_a_document_recipe_with_no_tags.dart';
import './../../step/the_library_home_screen_is_showing_with_tagged_documents.dart';
import './../../step/i_open_the_tag_filter_and_select_work.dart';
import './../../step/i_see_the_document_invoice.dart';
import './../../step/i_do_not_see_the_document_recipe.dart';

void main() {
  group('''Tag filtering''', () {
    testWidgets('''Filter documents by tag''', (tester) async {
      await theLibraryHasADocumentInvoiceTaggedWork(tester);
      await theLibraryHasADocumentRecipeWithNoTags(tester);
      await theLibraryHomeScreenIsShowingWithTaggedDocuments(tester);
      await iOpenTheTagFilterAndSelectWork(tester);
      await iSeeTheDocumentInvoice(tester);
      await iDoNotSeeTheDocumentRecipe(tester);
    });
  });
}
