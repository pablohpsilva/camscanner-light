// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import './../../step/the_library_has_a_document_invoice_with_no_folder.dart';
import './../../step/the_library_organize_screen_is_showing.dart';
import './../../step/i_move_the_document_invoice_to_a_new_folder_work.dart';
import './../../step/the_document_invoice_appears_under_the_folder_work.dart';
import './../../step/the_library_has_a_document_invoice_with_no_tags.dart';
import './../../step/i_add_the_tag_important_to_the_document_invoice.dart';
import './../../step/the_document_invoice_shows_a_tag_chip_important.dart';

void main() {
  group('''Organizing documents''', () {
    testWidgets('''Move a document to a folder from its menu''',
        (tester) async {
      await theLibraryHasADocumentInvoiceWithNoFolder(tester);
      await theLibraryOrganizeScreenIsShowing(tester);
      await iMoveTheDocumentInvoiceToANewFolderWork(tester);
      await theDocumentInvoiceAppearsUnderTheFolderWork(tester);
    });
    testWidgets('''Add a tag to a document from its menu''', (tester) async {
      await theLibraryHasADocumentInvoiceWithNoTags(tester);
      await theLibraryOrganizeScreenIsShowing(tester);
      await iAddTheTagImportantToTheDocumentInvoice(tester);
      await theDocumentInvoiceShowsATagChipImportant(tester);
    });
  });
}
