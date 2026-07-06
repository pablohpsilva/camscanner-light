import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/file_archiver.dart';

void main() {
  late Directory base;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('archiver');
  });

  tearDown(() async {
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<File> tmp(String name, String content) async {
    final f = File('${base.path}/$name');
    await f.writeAsString(content);
    return f;
  }

  test('zips files into a temp .zip whose entries round-trip', () async {
    final a = await tmp('a.pdf', 'AAA');
    final b = await tmp('b.pdf', 'BBB');

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: const ['Report.pdf', 'Invoice.pdf'],
    );

    expect(zip.path, endsWith('documents.zip'));
    expect(zip.path.startsWith(Directory.systemTemp.path), isTrue);
    expect(await zip.exists(), isTrue);

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['Report.pdf', 'Invoice.pdf']);
    expect(String.fromCharCodes(archive.files[0].content as List<int>), 'AAA');
    expect(String.fromCharCodes(archive.files[1].content as List<int>), 'BBB');
  });

  test('de-duplicates colliding entry names with a numeric suffix', () async {
    final a = await tmp('a.pdf', 'AAA');
    final b = await tmp('b.pdf', 'BBB');

    final zip = await const SystemFileArchiver().zip(
      [a, b],
      archiveName: 'documents.zip',
      entryNames: const ['Report.pdf', 'Report.pdf'],
    );

    final archive = ZipDecoder().decodeBytes(await zip.readAsBytes());
    expect(archive.files.map((f) => f.name), ['Report.pdf', 'Report (2).pdf']);
  });
}
