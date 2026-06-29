import 'dart:io';

import 'package:exif/exif.dart';

/// Reads a JPEG and FAILS (exit 1, prints EXIF_DIRTY) if any identifying tag is
/// present; passes (exit 0, prints `EXIF_CLEAN orientation=<...>`) otherwise.
/// Used by the b1 REAL_DEVICE lane to prove the on-device save is scrubbed.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/exif_check.dart <file.jpg>');
    exit(2);
  }
  final tags = await readExifFromBytes(File(args[0]).readAsBytesSync());
  const forbidden = [
    'Image Make',
    'Image Model',
    'Image Software',
    'Image DateTime',
    'EXIF DateTimeOriginal',
  ];
  final dirty = <String>[
    ...forbidden.where(tags.containsKey),
    ...tags.keys.where((k) => k.startsWith('GPS')),
  ];
  if (dirty.isNotEmpty) {
    stdout.writeln('EXIF_DIRTY: ${dirty.join(", ")}');
    exit(1);
  }
  stdout.writeln('EXIF_CLEAN orientation=${tags['Image Orientation'] ?? "none"}');
}
