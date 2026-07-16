import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The shared enhancer isolate body (P09): decode the JPEG, bake EXIF
/// orientation into pixels (the scrubber keeps the Orientation tag but encodeJpg
/// strips EXIF), apply [op] to the oriented image, and re-encode at [quality].
/// On ANY failure — corrupt/undecodable bytes included — the original [bytes]
/// are returned unchanged, honouring the enhancers' "never lose a page" contract.
///
/// [op] is the mode's `*Oriented` transform (autoEnhanceOriented /
/// colorEnhanceOriented / grayscaleEnhanceOriented); [quality] is 95 for Auto,
/// 92 for the others. Byte-identical to the three previously-duplicated isolate
/// bodies it replaces.
Uint8List runOrientedEnhance(
  Uint8List bytes,
  img.Image Function(img.Image) op, {
  int quality = 92,
}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    final oriented = img.bakeOrientation(decoded);
    return Uint8List.fromList(img.encodeJpg(op(oriented), quality: quality));
  } catch (_) {
    return bytes;
  }
}
