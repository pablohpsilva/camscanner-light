import 'package:flutter/material.dart';

/// How the user wants multiple selected documents exported.
enum MultiExportChoice {
  /// One combined PDF containing every page of every selected document.
  merged,

  /// One PDF per document, bundled into a single `.zip`.
  separateZip,
}

/// Asks the user how to export 2+ selected documents. Returns the chosen mode,
/// or null when dismissed. Shown only for multi-selection (a single document
/// exports directly, no dialog).
Future<MultiExportChoice?> showExportChoiceDialog(BuildContext context) {
  return showDialog<MultiExportChoice>(
    context: context,
    builder: (_) => SimpleDialog(
      key: const Key('export-choice-dialog'),
      title: const Text('Export documents'),
      children: [
        SimpleDialogOption(
          key: const Key('export-choice-merged'),
          onPressed: () =>
              Navigator.of(context).pop(MultiExportChoice.merged),
          child: const ListTile(
            leading: Icon(Icons.picture_as_pdf_outlined),
            title: Text('Merge into one PDF'),
          ),
        ),
        SimpleDialogOption(
          key: const Key('export-choice-zip'),
          onPressed: () =>
              Navigator.of(context).pop(MultiExportChoice.separateZip),
          child: const ListTile(
            leading: Icon(Icons.folder_zip_outlined),
            title: Text('Separate PDFs (.zip)'),
          ),
        ),
      ],
    ),
  );
}
