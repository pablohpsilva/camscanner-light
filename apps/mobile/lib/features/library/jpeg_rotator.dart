import 'package:flutter/foundation.dart' show Uint8List, compute;
import 'package:image/image.dart' as img;

/// Rotates + re-encodes JPEG bytes off the UI isolate (P05 TEST-01). Injectable
/// so the derivative pipeline can be host-tested with a fake instead of a real
/// `compute()` isolate; production uses [ComputeJpegRotator].
abstract interface class JpegRotator {
  /// Decodes [bytes], bakes EXIF orientation, rotates [quarterTurns] * 90° CW,
  /// and re-encodes as JPEG. Returns null when [bytes] can't be decoded — the
  /// caller maps that (and a timeout) onto the rotate-error contract.
  Future<Uint8List?> rotate(Uint8List bytes, int quarterTurns);
}

/// Production [JpegRotator]: runs [rotateAndBakeJpeg] in a `compute` isolate so
/// the CPU-heavy full-res decode/rotate/encode never freezes the UI isolate.
class ComputeJpegRotator implements JpegRotator {
  const ComputeJpegRotator();

  @override
  Future<Uint8List?> rotate(Uint8List bytes, int quarterTurns) =>
      compute(rotateAndBakeJpeg, RotateJpegArgs(bytes, quarterTurns));
}

/// Arguments for [rotateAndBakeJpeg] — must be a top-level type so it can cross
/// the isolate boundary used by `compute`.
class RotateJpegArgs {
  final Uint8List bytes;
  final int quarterTurns;
  const RotateJpegArgs(this.bytes, this.quarterTurns);
}

/// Isolate entrypoint (top-level, for `compute`): decode [args.bytes], bake EXIF
/// orientation into the pixels (matches every other pixel path), rotate 90°*
/// quarterTurns clockwise, and re-encode as JPEG. Returns null if the bytes
/// can't be decoded. Full-res decode/rotate/encode is CPU-heavy, so this runs
/// off the UI isolate to keep edits from freezing it.
Uint8List? rotateAndBakeJpeg(RotateJpegArgs args) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(args.bytes);
  } catch (_) {
    decoded = null;
  }
  if (decoded == null) return null;
  final upright = img.bakeOrientation(decoded);
  final rotated = img.copyRotate(upright, angle: 90 * args.quarterTurns);
  return Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
}
