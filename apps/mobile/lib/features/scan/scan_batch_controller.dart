import '../library/crop_corners.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'captured_image.dart';

/// Outcome of a [ScanBatchController.saveBatch] run. The caller owns ALL UI,
/// strings, and navigation — this only reports what persistence did, so each
/// scan flow can apply its own policy (the document scan retries; the ID scan
/// pops with its own error strings and then marks the doc as an ID card).
sealed class ScanBatchResult {
  const ScanBatchResult();
}

/// The run was abandoned because the caller went inactive (widget unmounted)
/// mid-batch — the caller should do nothing, mirroring the old
/// `if (!mounted) return` guards that stopped the save loop on navigation.
class ScanBatchCancelled extends ScanBatchResult {
  const ScanBatchCancelled();
}

/// The FIRST page failed to save, so no document exists.
class ScanBatchSaveFailed extends ScanBatchResult {
  const ScanBatchSaveFailed();
}

/// The document was created ([documentId]); [pageCount] pages landed.
/// [failedPageIndices] lists any subsequent pages (index into the input list)
/// whose `addPage` failed — the caller decides whether that matters (the doc
/// scan tolerates it, the ID scan surfaces it).
class ScanBatchSaved extends ScanBatchResult {
  final int documentId;
  final int pageCount;
  final List<int> failedPageIndices;
  const ScanBatchSaved({
    required this.documentId,
    required this.pageCount,
    this.failedPageIndices = const [],
  });
}

/// Batch save/add-page use-case shared by the document scan ([ScanScreen]) and
/// the ID scan ([IdScanScreen]) (P07): persist page 0 with [SaveController.save],
/// then each remaining page with [SaveController.addPage], all at [corners].
/// Plain Dart — no widgets — so the save-first-then-loop state machine is
/// unit-testable without a widget pump; the two screens previously each carried
/// their own copy of it.
class ScanBatchController {
  final SaveController _saveController;

  // ignore: prefer_initializing_formals
  const ScanBatchController(this._saveController);

  /// Saves [pages] as ONE document with the given [enhancer]. Reports the
  /// running page count to [onProgress] as each page lands (so the caller can
  /// update a live title). [active] is polled after every persistence await —
  /// when it returns false (the caller unmounted) the run stops and returns
  /// [ScanBatchCancelled], exactly reproducing the old per-await mounted guard.
  Future<ScanBatchResult> saveBatch(
    List<CapturedImage> pages,
    ImageEnhancer enhancer, {
    CropCorners corners = CropCorners.fullFrame,
    required bool Function() active,
    void Function(int pageCount)? onProgress,
  }) async {
    final doc = await _saveController.save(
      pages.first,
      corners: corners,
      enhancer: enhancer,
    );
    if (!active()) return const ScanBatchCancelled();
    if (doc == null) return const ScanBatchSaveFailed();
    onProgress?.call(1);

    var pageCount = 1;
    final failed = <int>[];
    for (var i = 1; i < pages.length; i++) {
      final pos = await _saveController.addPage(
        pages[i],
        doc.id,
        corners: corners,
        enhancer: enhancer,
      );
      if (!active()) return const ScanBatchCancelled();
      if (pos != null) {
        pageCount = pos;
        onProgress?.call(pageCount);
      } else {
        failed.add(i);
      }
    }
    return ScanBatchSaved(
      documentId: doc.id,
      pageCount: pageCount,
      failedPageIndices: failed,
    );
  }
}
