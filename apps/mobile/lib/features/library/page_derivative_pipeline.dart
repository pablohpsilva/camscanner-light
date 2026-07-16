import 'dart:io';
import 'dart:typed_data';

import '../../core/async/with_isolate_timeout.dart';
import 'crop_corners.dart';
import 'document_file_store.dart';
import 'document_repository.dart' show DocumentSaveException;
import 'enhancer_mode.dart';
import 'jpeg_rotator.dart';
import 'page_processor.dart';

/// Regenerates a page's display ("flat") derivative from its PRISTINE base by
/// applying enhance ∘ rotate ∘ crop (P05 CPLX-01). Extracted from the God
/// repository's `_writeFlat` and split into explicit, individually-testable
/// stages; NEVER writes the base. [corners] are in the display frame
/// (post-rotation). Holds the page processor + file store and an injectable
/// [JpegRotator] so rotation is host-testable.
class PageDerivativePipeline {
  final DocumentFileStore _fileStore;
  final PageProcessor _processor;
  final JpegRotator _rotator;

  /// Upper bound on the rotate decode+rotate+re-encode isolate (CMP-10). A
  /// wedged isolate cannot be killed from Dart, so this only detaches the
  /// awaiting future; on expiry the rotate surfaces the same
  /// [DocumentSaveException] as an undecodable base.
  final Duration rotateTimeout;

  const PageDerivativePipeline({
    required DocumentFileStore fileStore,
    required PageProcessor processor,
    JpegRotator rotator = const ComputeJpegRotator(),
    this.rotateTimeout = const Duration(seconds: 12),
  }) : _fileStore = fileStore, // ignore: prefer_initializing_formals
       _processor = processor, // ignore: prefer_initializing_formals
       _rotator = rotator; // ignore: prefer_initializing_formals

  /// Regenerates the flat and returns its relative path, or null when the
  /// display equals the base (no rotation, no crop, no filter) or the pipeline
  /// makes nothing.
  Future<String?> writeFlat({
    required String relativeImagePath,
    required int quarterTurns,
    required CropCorners corners,
    required EnhancerMode mode,
    required String? existingFlatRel,
  }) async {
    final baseBytes = await _fileStore
        .absoluteFor(relativeImagePath)
        .readAsBytes();
    final isFullFrame = corners == CropCorners.fullFrame;

    // Fast path: the display equals the pristine base — no image work at all.
    if (_shouldSkip(quarterTurns, isFullFrame, mode)) {
      await _deleteFlatIfPresent(existingFlatRel);
      return null;
    }

    // Rotation needs a full-res decode+rotate+re-encode — run it OFF the UI
    // isolate. quarterTurns == 0 skips it (the processor bakes EXIF orientation
    // itself), so it consumes the base bytes directly.
    final rotatedBytes = quarterTurns == 0
        ? null
        : await _rotate(baseBytes, quarterTurns);
    final input = rotatedBytes ?? baseBytes;

    final flatBytes = isFullFrame
        ? await _enhanceFullFrame(input, mode, rotatedBytes)
        : await _warpAndEnhanceCrop(input, corners, mode, rotatedBytes);

    return _finalizeFlat(flatBytes, relativeImagePath, existingFlatRel);
  }

  /// The display is byte-identical to the pristine base: no rotation, full
  /// frame, no filter.
  bool _shouldSkip(int quarterTurns, bool isFullFrame, EnhancerMode mode) =>
      quarterTurns == 0 && isFullFrame && mode == EnhancerMode.none;

  /// Off-isolate rotate, guarded by [rotateTimeout] (CMP-10). A wedged isolate
  /// can't be killed from Dart, so on expiry we detach and surface the SAME
  /// failure contract as an undecodable base. Returns the rotated bytes.
  Future<Uint8List> _rotate(Uint8List baseBytes, int quarterTurns) async {
    final rotated = await withIsolateTimeout(
      () => _rotator.rotate(baseBytes, quarterTurns),
      timeout: rotateTimeout,
      onTimeout: () => throw const DocumentSaveException(
        'regenerate: undecodable base image',
      ),
    );
    if (rotated == null) {
      throw const DocumentSaveException('regenerate: undecodable base image');
    }
    return rotated;
  }

  /// Full-frame flat: pure rotation returns the rotated bytes as-is; otherwise
  /// enhance, falling back to the un-enhanced frame on failure so a page is
  /// never lost. [rotatedBytes] is null when there was no rotation.
  Future<Uint8List?> _enhanceFullFrame(
    Uint8List input,
    EnhancerMode mode,
    Uint8List? rotatedBytes,
  ) async {
    if (mode == EnhancerMode.none) {
      // quarterTurns != 0 here (pure pass-through handled by the fast path).
      return rotatedBytes;
    }
    return await _processor.process(input, CropCorners.fullFrame, mode) ??
        input;
  }

  /// Cropped flat: the processor warps + enhances in one pass (or two-step for a
  /// stubbed warper). Falls back to the rotated-only image if it makes nothing.
  Future<Uint8List?> _warpAndEnhanceCrop(
    Uint8List input,
    CropCorners corners,
    EnhancerMode mode,
    Uint8List? rotatedBytes,
  ) async => await _processor.process(input, corners, mode) ?? rotatedBytes;

  /// Writes the flat and returns its path, or (when there is nothing to write)
  /// deletes any existing flat and returns null.
  Future<String?> _finalizeFlat(
    Uint8List? flatBytes,
    String relativeImagePath,
    String? existingFlatRel,
  ) async {
    if (flatBytes == null) {
      await _deleteFlatIfPresent(existingFlatRel);
      return null;
    }
    final flatRel =
        existingFlatRel ?? _fileStore.flatForImage(relativeImagePath);
    await _fileStore.writeRelative(flatRel, flatBytes);
    return flatRel;
  }

  Future<void> _deleteFlatIfPresent(String? rel) async {
    if (rel == null) return;
    try {
      await _fileStore.absoluteFor(rel).delete();
    } on FileSystemException {
      /* already gone — fine */
    }
  }
}
