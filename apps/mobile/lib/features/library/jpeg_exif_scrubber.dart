import 'dart:typed_data';

import 'image_metadata_scrubber.dart';

/// Lossless, byte-level JPEG EXIF scrubber. Drops APP1 (Exif/XMP) and APP13
/// (Photoshop/IPTC) application segments, keeps APP0/APP2 and all coding
/// segments byte-for-byte, and re-emits a minimal canonical Exif APP1 carrying
/// ONLY the original's Orientation. Whitelist, not blacklist: nothing
/// identifying can leak. Does NOT decode/re-encode — that would auto-orient and
/// drop the tag (verified in the B1 spike).
class JpegExifScrubber implements ImageMetadataScrubber {
  const JpegExifScrubber();

  @override
  Uint8List scrub(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const MetadataScrubException('not a JPEG (missing SOI)');
    }
    final orientation = _readOrientation(bytes); // default 1 if absent
    final out = BytesBuilder();
    out.add([0xFF, 0xD8]); // SOI
    out.add(_minimalExifApp1(orientation));

    var i = 2;
    while (i < bytes.length) {
      if (bytes[i] != 0xFF) {
        throw const MetadataScrubException('corrupt JPEG (expected marker)');
      }
      if (i + 1 >= bytes.length) {
        throw const MetadataScrubException('truncated JPEG (dangling 0xFF)');
      }
      final marker = bytes[i + 1];
      if (marker == 0xDA) {
        out.add(bytes.sublist(i)); // SOS + entropy data + EOI verbatim
        break;
      }
      if (i + 4 > bytes.length) {
        throw const MetadataScrubException('truncated JPEG segment');
      }
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      final segEnd = i + 2 + len;
      if (segEnd > bytes.length) {
        throw const MetadataScrubException('JPEG segment overruns buffer');
      }
      // Drop APP1 (0xE1: Exif/XMP) and APP13 (0xED: Photoshop/IPTC); copy the
      // rest (APP0 JFIF, APP2 ICC, DQT/DHT/SOF/...).
      if (marker != 0xE1 && marker != 0xED) {
        out.add(bytes.sublist(i, segEnd));
      }
      i = segEnd;
    }
    return out.toBytes();
  }

  /// A minimal valid Exif APP1 (big-endian TIFF, IFD0 with one Orientation
  /// SHORT, no next IFD). Validated end-to-end on-device in the B1 spike.
  List<int> _minimalExifApp1(int orientation) {
    final tiff = <int>[
      0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // 'MM', 42, IFD0 @ 8
      0x00, 0x01, // 1 entry
      0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, n=1
      (orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00, // value
      0x00, 0x00, 0x00, 0x00, // next IFD = 0
    ];
    final payload = <int>[
      0x45,
      0x78,
      0x69,
      0x66,
      0x00,
      0x00,
      ...tiff,
    ]; // 'Exif\0\0'
    final len = payload.length + 2;
    return <int>[0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...payload];
  }

  /// Reads IFD0 Orientation (tag 0x0112) from the first APP1/Exif segment.
  /// Returns 1 if absent/unreadable (a safe default — upright).
  int _readOrientation(Uint8List b) {
    var i = 2;
    while (i + 4 <= b.length) {
      if (b[i] != 0xFF) return 1;
      final marker = b[i + 1];
      if (marker == 0xDA) return 1; // reached scan; no Exif
      final len = (b[i + 2] << 8) | b[i + 3];
      final segEnd = i + 2 + len;
      if (segEnd > b.length) return 1;
      if (marker == 0xE1 &&
          len >= 8 &&
          b[i + 4] == 0x45 &&
          b[i + 5] == 0x78 &&
          b[i + 6] == 0x69 &&
          b[i + 7] == 0x66) {
        return _orientationFromTiff(b, i + 4 + 6, segEnd) ?? 1;
      }
      i = segEnd;
    }
    return 1;
  }

  int? _orientationFromTiff(Uint8List b, int tiffStart, int end) {
    if (tiffStart + 8 > end) return null;
    final big = b[tiffStart] == 0x4D; // 'MM' big-endian, else 'II' little
    int u16(int o) => big ? (b[o] << 8) | b[o + 1] : (b[o + 1] << 8) | b[o];
    int u32(int o) => big
        ? (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
        : (b[o + 3] << 24) | (b[o + 2] << 16) | (b[o + 1] << 8) | b[o];
    final ifd0 = tiffStart + u32(tiffStart + 4);
    if (ifd0 + 2 > end) return null;
    final count = u16(ifd0);
    var e = ifd0 + 2;
    for (var k = 0; k < count && e + 12 <= end; k++, e += 12) {
      if (u16(e) == 0x0112) return u16(e + 8); // Orientation value (SHORT)
    }
    return null;
  }
}
