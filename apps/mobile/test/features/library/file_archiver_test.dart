import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:mobile/features/library/file_archiver.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('archiver_test');
  });
  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<File> writeFile(String name, List<int> bytes) async {
    final f = File(p.join(base.path, name));
    await f.writeAsBytes(bytes);
    return f;
  }

  test('zips N files with the given entry names, round-tripping bytes', () async {
    final a = await writeFile('a.pdf', [1, 2, 3]);
    final b = await writeFile('b.pdf', [4, 5, 6, 7]);

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: ['a.pdf', 'b.pdf'],
    );

    // Output is a temp .zip, not inside the source dir.
    expect(zip.path, endsWith('documents.zip'));
    expect(p.isWithin(base.path, zip.path), isFalse);

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name).toList(), ['a.pdf', 'b.pdf']);
    expect(archive.files[0].content, equals(Uint8List.fromList([1, 2, 3])));
    expect(archive.files[1].content, equals(Uint8List.fromList([4, 5, 6, 7])));
  });

  test('stores entries uncompressed (no deflate)', () async {
    final a = await writeFile('a.pdf', List<int>.filled(1024, 42));
    final zip = await const SystemFileArchiver()
        .zip([a], archiveName: 'x.zip', entryNames: ['a.pdf']);
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.single.compression, CompressionType.none);
  });

  test('de-duplicates colliding entry names with a numeric suffix', () async {
    final a = await writeFile('one.pdf', [1]);
    final b = await writeFile('two.pdf', [2]);
    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'dup.zip',
      entryNames: ['Doc.pdf', 'Doc.pdf'],
    );
    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name).toList(), ['Doc.pdf', 'Doc (2).pdf']);
  });
}
