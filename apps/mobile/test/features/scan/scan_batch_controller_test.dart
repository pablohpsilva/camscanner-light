import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/library/save_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/scan_batch_controller.dart';

import '../../support/fake_library.dart';

/// P07 Task 1: the save-first-then-loop-addPage batch state machine, previously
/// hand-rolled inside scan_screen AND id_scan_screen, is now a plain-Dart
/// use-case unit-tested with NO widget pump.
void main() {
  ScanBatchController controllerFor(FakeDocumentRepository repo) =>
      ScanBatchController(SaveController(repository: repo));

  List<CapturedImage> images(int n) =>
      List.generate(n, (i) => CapturedImage('/nonexistent/p$i.jpg'));

  test('saves the first page, then addPages the rest in order', () async {
    final repo = FakeDocumentRepository();
    final result = await controllerFor(
      repo,
    ).saveBatch(images(3), const NoneEnhancer(), active: () => true);

    expect(result, isA<ScanBatchSaved>());
    final saved = result as ScanBatchSaved;
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 2);
    expect(saved.pageCount, 3); // fake addPage returns 2 then 3
    expect(saved.failedPageIndices, isEmpty);
    expect(repo.lastSavedCorners, CropCorners.fullFrame);
  });

  test('a single page saves with no addPage', () async {
    final repo = FakeDocumentRepository();
    final result = await controllerFor(
      repo,
    ).saveBatch(images(1), const NoneEnhancer(), active: () => true);

    expect(result, isA<ScanBatchSaved>());
    expect((result as ScanBatchSaved).pageCount, 1);
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 0);
  });

  test('first-page save failure → ScanBatchSaveFailed, no addPage attempted',
      () async {
    final repo = FakeDocumentRepository(throwOnCreate: true);
    final result = await controllerFor(
      repo,
    ).saveBatch(images(3), const NoneEnhancer(), active: () => true);

    expect(result, isA<ScanBatchSaveFailed>());
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 0);
  });

  test('an addPage failure is reported but does not abort the doc', () async {
    final repo = FakeDocumentRepository(throwOnAddPage: true);
    final result = await controllerFor(
      repo,
    ).saveBatch(images(2), const NoneEnhancer(), active: () => true);

    expect(result, isA<ScanBatchSaved>());
    final saved = result as ScanBatchSaved;
    expect(saved.pageCount, 1); // first page landed; back failed
    expect(saved.failedPageIndices, [1]);
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 1);
  });

  test('inactive right after the first save → Cancelled, no addPage loop',
      () async {
    // The save itself does not consult active(); the check fires immediately
    // after it (mirrors the old `if (!mounted) return` after the save await).
    final repo = FakeDocumentRepository();
    final result = await controllerFor(
      repo,
    ).saveBatch(images(3), const NoneEnhancer(), active: () => false);

    expect(result, isA<ScanBatchCancelled>());
    expect(repo.createCalls, 1); // the doc was created before the cancel check
    expect(repo.addPageCalls, 0);
  });

  test('going inactive mid-loop stops adding further pages', () async {
    // active() is called once after the save, then once after each addPage.
    // Stay active for the post-save check + the first addPage, then go inactive.
    final repo = FakeDocumentRepository();
    var n = 0;
    final result = await controllerFor(
      repo,
    ).saveBatch(images(4), const NoneEnhancer(), active: () => ++n <= 2);

    expect(result, isA<ScanBatchCancelled>());
    expect(repo.createCalls, 1);
    expect(repo.addPageCalls, 2); // added two pages, then cancelled
  });

  test('reports progress as each page lands', () async {
    final repo = FakeDocumentRepository();
    final progress = <int>[];
    await controllerFor(repo).saveBatch(
      images(3),
      const NoneEnhancer(),
      active: () => true,
      onProgress: progress.add,
    );
    expect(progress, [1, 2, 3]);
  });
}
