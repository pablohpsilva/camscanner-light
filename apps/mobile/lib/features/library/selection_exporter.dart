import 'package:path/path.dart' as p;

import 'document_repository.dart';
import 'document_summary.dart';
import 'file_archiver.dart';
import 'share_channel.dart';

/// The multi-select export policy (P06 task 3), lifted verbatim from
/// `HomeScreen._exportSelected`: a single selected document shares one PDF;
/// several share a zip of per-document PDFs whose in-zip names reuse the repo's
/// sanitized PDF filenames. Pure domain logic over injected collaborators — no
/// widgets, no snackbars, no busy flag — so the decision is unit-testable.
class SelectionExporter {
  final DocumentRepository _repository;
  final ShareChannel _share;
  final FileArchiver _archiver;

  const SelectionExporter({
    required DocumentRepository repository,
    required ShareChannel share,
    required FileArchiver archiver,
  }) : _repository = repository,
       _share = share,
       _archiver = archiver;

  /// Exports [selected] (must be non-empty) and hands it to the share sheet.
  /// One document → a single PDF with its name as the subject; many → a
  /// `documents.zip` of per-document PDFs. Throws on any export/share failure
  /// (the caller owns the busy flag + toast).
  Future<void> exportAndShare(List<DocumentSummary> selected) async {
    final ids = selected.map((s) => s.document.id).toList();
    if (ids.length == 1) {
      final file = await _repository.exportPdf(ids.first);
      await _share.share([file.path], subject: selected.first.document.name);
    } else {
      final files = await _repository.exportSeparatePdfs(ids);
      // Reuse the repo's sanitized per-doc PDF names as zip entry names (DRY).
      final entryNames = [for (final f in files) p.basename(f.path)];
      final zip = await _archiver.zip(
        files,
        archiveName: 'documents.zip',
        entryNames: entryNames,
      );
      await _share.share([zip.path], mimeType: 'application/zip');
    }
  }
}
