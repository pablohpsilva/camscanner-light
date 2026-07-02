// apps/mobile/test/features/library/pdf/pdf_builder_quality_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

Future<PageImage> _largePage(Directory dir) async {
  final image = img.Image(width: 3000, height: 2000);
  for (var y = 0; y < 2000; y += 1) {
    for (var x = 0; x < 3000; x += 1) {
      image.setPixelRgb(x, y, x % 256, y % 256, (x + y) % 256);
    }
  }
  final path = '${dir.path}/page.jpg';
  await File(path).writeAsBytes(img.encodeJpg(image, quality: 95));
  return PageImage(
    position: 1,
    imagePath: path,
    ocrWords: const [
      OcrWordBox(text: 'HELLO', left: .1, top: .1, right: .4, bottom: .2),
    ],
    ocrText: 'HELLO',
  );
}

void main() {
  test('low quality yields a smaller PDF than original for a large page',
      () async {
    final dir = await Directory.systemTemp.createTemp('pdfq');
    final page = await _largePage(dir);
    const builder = PdfBuilder();
    final original = await builder.build([page], quality: ExportQuality.original);
    final low = await builder.build([page], quality: ExportQuality.low);
    expect(low.length, lessThan(original.length));
    await dir.delete(recursive: true);
  });

  test('searchable text survives bake+downscale at low quality', () async {
    final dir = await Directory.systemTemp.createTemp('pdfq2');
    final page = await _largePage(dir);
    const builder = PdfBuilder(textLayer: OcrPdfTextLayer());
    // compress:false keeps the text stream un-deflated so it is greppable.
    final low =
        await builder.build([page], quality: ExportQuality.low, compress: false);
    expect(String.fromCharCodes(low).contains('HELLO'), isTrue);
    await dir.delete(recursive: true);
  });
}
