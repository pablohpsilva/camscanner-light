import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

Future<String> _writeJpg(String name, int w, int h) async {
  final dir = await Directory.systemTemp.createTemp('idpdf');
  final f = File('${dir.path}/$name.jpg');
  await f.writeAsBytes(img.encodeJpg(img.Image(width: w, height: h)));
  return f.path;
}

void main() {
  test('idCardLayout puts both images on ONE page', () async {
    final front = await _writeJpg('front', 300, 190);
    final back = await _writeJpg('back', 300, 190);
    final pages = [
      PageImage(position: 1, imagePath: front),
      PageImage(position: 2, imagePath: back),
    ];
    final bytes = await const PdfBuilder().build(
      pages,
      compress: false,
      idCardLayout: true,
    );
    final s = String.fromCharCodes(bytes);
    expect(s.startsWith('%PDF-'), isTrue);
    // exactly one /Page (not /Pages)
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 1);
    // both images embedded
    expect(RegExp(r'/Subtype\s*/Image').allMatches(s).length, 2);
  });

  test(
    'default layout (idCardLayout false) still one page per image',
    () async {
      final f1 = await _writeJpg('a', 300, 190);
      final f2 = await _writeJpg('b', 300, 190);
      final bytes = await const PdfBuilder().build([
        PageImage(position: 1, imagePath: f1),
        PageImage(position: 2, imagePath: f2),
      ], compress: false);
      final s = String.fromCharCodes(bytes);
      expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 2);
    },
  );
}
