import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';

// Walk JPEG segments honoring lengths to find the MAIN-image SOS (0xFFDA),
// skipping APP1 and any thumbnail JPEG embedded inside it. A naive "first FFDA"
// scan would lock onto an embedded thumbnail and falsely report "differs".
int _mainSos(List<int> b) {
  var i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) {
      throw StateError('bad marker @ $i');
    }
    if (b[i + 1] == 0xDA) return i;
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
  }
  throw StateError('no main SOS');
}

void main() {
  final scrubber = const JpegExifScrubber();
  late Uint8List sample;

  setUpAll(() {
    sample = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
  });

  test('removes identifying EXIF but keeps Orientation', () async {
    final before = await readExifFromBytes(sample);
    expect(before['Image Make'], isNotNull, reason: 'fixture sanity');
    expect(before['Image Orientation'].toString(), 'Rotated 90 CW');

    final out = scrubber.scrub(sample);
    final after = await readExifFromBytes(out);

    expect(after['Image Make'], isNull);
    expect(after['Image Model'], isNull);
    expect(after['Image Software'], isNull);
    expect(after['Image DateTime'], isNull);
    expect(after.keys.where((k) => k.startsWith('GPS')), isEmpty);
    expect(
      after['Image Orientation'].toString(),
      'Rotated 90 CW',
      reason: 'Orientation must survive (kept losslessly)',
    );
  });

  test('is lossless — main image scan data is byte-identical', () {
    final out = scrubber.scrub(sample);
    final a = sample.sublist(_mainSos(sample));
    final b = out.sublist(_mainSos(out));
    expect(b, equals(a));
  });

  test('throws MetadataScrubException on non-JPEG input', () {
    expect(
      () => scrubber.scrub(Uint8List.fromList([0, 1, 2, 3])),
      throwsA(isA<MetadataScrubException>()),
    );
  });

  test('throws MetadataScrubException on a truncated JPEG (dangling 0xFF)', () {
    expect(
      () => scrubber.scrub(Uint8List.fromList([0xFF, 0xD8, 0xFF])),
      throwsA(isA<MetadataScrubException>()),
    );
  });
}
