import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'export_quality.dart';

/// Re-encodes a page's JPEG for a chosen [ExportQuality] (DIP seam). The image
/// leaving the app is compressed; the stored original is never touched.
abstract interface class ImageCompressor {
  /// Returns re-encoded JPEG bytes for [quality], or the input bytes verbatim
  /// when [quality] does not re-encode (ExportQuality.original) or the input is
  /// not decodable.
  Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality);
}

/// Production compressor: pure-Dart `image` package, following the same
/// decode→bakeOrientation→[resize]→encodeJpg sequence every other re-encode
/// path in the app uses (auto_enhancer, perspective_warper, filter strip, …).
class ImageLibraryCompressor implements ImageCompressor {
  const ImageLibraryCompressor();

  @override
  Future<Uint8List> compress(Uint8List jpegBytes, ExportQuality quality) async {
    if (!quality.reencodes) return jpegBytes; // Original: verbatim, no decode.

    img.Image? decoded;
    try {
      decoded = img.decodeImage(jpegBytes);
    } catch (_) {
      decoded = null; // the image pkg can THROW on garbage, not just return null
    }
    if (decoded == null) return jpegBytes; // fallback: never fail an export

    // bakeOrientation: encodeJpg drops EXIF, so pixels must be upright first.
    var image = img.bakeOrientation(decoded);

    final cap = quality.maxDimension;
    if (cap != null) {
      final longEdge = image.width >= image.height ? image.width : image.height;
      if (longEdge > cap) {
        // Pass only the long edge; the package derives the other side (aspect
        // preserved). Never upscale (guarded by longEdge > cap above).
        image = image.width >= image.height
            ? img.copyResize(image,
                width: cap, interpolation: img.Interpolation.average)
            : img.copyResize(image,
                height: cap, interpolation: img.Interpolation.average);
      }
    }

    return Uint8List.fromList(
        img.encodeJpg(image, quality: quality.jpegQuality!));
  }
}
