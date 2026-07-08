import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Ensures [bytes] are JPEG so the JPEG-only metadata scrubber and the JPEG
/// storage pipeline can process them.
///
/// - Already-JPEG bytes (SOI marker `0xFF 0xD8`) are returned unchanged (no
///   re-encode → no quality loss, fast).
/// - Other decodable images (e.g. the PNG that VisionKit / a gallery import can
///   produce) are decoded and re-encoded to JPEG. The re-encode also drops all
///   source metadata, which the scrubber then re-verifies.
/// - Non-image bytes are returned unchanged, so the downstream scrubber still
///   fails closed on genuinely unprocessable input (never write unverified data).
Uint8List ensureJpegBytes(Uint8List bytes, {int quality = 90}) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xD8) return bytes;
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    return img.encodeJpg(decoded, quality: quality);
  } catch (_) {
    // Undecodable/corrupt input — hand the original bytes to the scrubber,
    // which fails closed. Never write unverified data.
    return bytes;
  }
}
