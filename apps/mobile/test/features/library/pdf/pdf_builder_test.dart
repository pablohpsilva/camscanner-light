import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/pdf/pdf_text_layer.dart';
import 'package:pdf/widgets.dart' as pw;

// A spy text layer: records the pages it was asked about and returns a fixed overlay.
class _SpyTextLayer implements PdfTextLayer {
  final List<PageImage> calls = [];
  final List<pw.Widget> overlay;
  _SpyTextLayer({this.overlay = const []});
  @override
  List<pw.Widget> overlayFor(PageImage page) {
    calls.add(page);
    return overlay;
  }
}

bool _containsBytes(Uint8List hay, Uint8List needle) {
  for (var i = 0; i + needle.length <= hay.length; i++) {
    var ok = true;
    for (var j = 0; j < needle.length; j++) {
      if (hay[i + j] != needle[j]) { ok = false; break; }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  const fixturePath = 'test/fixtures/landscape_exif6.jpg';
  final jpeg = File(fixturePath).readAsBytesSync();
  PageImage page() => const PageImage(position: 1, imagePath: fixturePath);
  String dec(Uint8List b) => latin1.decode(b, allowInvalid: true);

  test('builds a valid single-page PDF', () async {
    final pdf = await const PdfBuilder().build([page()]);
    final s = dec(pdf);
    expect(s.startsWith('%PDF-'), isTrue);
    // robust page count: /Type /Page NOT followed by 's' (avoid /Pages)
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 1);
  });

  test('multi-page: one PDF page per input page, in order, at each image aspect',
      () async {
    // Three JPEGs with DISTINCT dimensions so each embedded image XObject's
    // /Width + /Height uniquely identify its page and encode order.
    // Return List<int> (writeAsBytesSync accepts it) so this is robust to
    // encodeJpg's return type across image package versions.
    List<int> makeJpeg(int w, int h) =>
        img.encodeJpg(img.Image(width: w, height: h));
    final tmp = Directory.systemTemp.createTempSync('h5builder');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final f1 = File('${tmp.path}/p1.jpg')..writeAsBytesSync(makeJpeg(120, 60));
    final f2 = File('${tmp.path}/p2.jpg')..writeAsBytesSync(makeJpeg(80, 160));
    final f3 = File('${tmp.path}/p3.jpg')..writeAsBytesSync(makeJpeg(200, 100));
    final pages = [
      PageImage(position: 1, imagePath: f1.path),
      PageImage(position: 2, imagePath: f2.path),
      PageImage(position: 3, imagePath: f3.path),
    ];

    final pdf = await const PdfBuilder().build(pages, compress: false);
    final s = dec(pdf);

    // Count: exactly three page objects (/Page not followed by 's' -> not /Pages).
    expect(RegExp(r'/Type\s*/Page(?![s])').allMatches(s).length, 3,
        reason: 'one PDF page per document page');

    // Order + aspect: the three embedded image XObjects (one per page) carry
    // /Width and /Height in page order. Image-only PDF => no other /Width.
    final widths = RegExp(r'/Width\s+(\d+)')
        .allMatches(s)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    final heights = RegExp(r'/Height\s+(\d+)')
        .allMatches(s)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    expect(widths, [120, 80, 200], reason: 'image widths follow page order');
    expect(heights, [60, 160, 100], reason: 'heights follow page order (aspect)');

    // Original aspect: each page's /MediaBox is sized to its own image — the
    // sequence (in page order) proves per-page aspect, not just the embedded
    // image dims. Exactly three MediaBoxes, no inherited root box.
    final mediaBoxes = RegExp(
            r'/MediaBox\s*\[\s*0(?:\.0)?\s+0(?:\.0)?\s+([\d.]+)\s+([\d.]+)')
        .allMatches(s)
        .map((m) =>
            '${double.parse(m.group(1)!).round()}x${double.parse(m.group(2)!).round()}')
        .toList();
    expect(mediaBoxes, ['120x60', '80x160', '200x100'],
        reason: 'each page MediaBox matches its image aspect, in page order');
  });

  test('embeds the JPEG losslessly (DCTDecode + verbatim bytes)', () async {
    final pdf = await const PdfBuilder().build([page()]);
    expect(dec(pdf).contains('/DCTDecode'), isTrue);
    expect(
      _containsBytes(pdf, jpeg.sublist(jpeg.length - 60, jpeg.length - 20)),
      isTrue,
      reason: 'raw JPEG bytes must be embedded verbatim (no re-encode)',
    );
  });

  test('auto-orients: EXIF-6 200x100 fixture -> oriented page 100x200', () async {
    final pdf = await const PdfBuilder().build([page()]);
    final m = RegExp(r'/MediaBox\s*\[\s*0\s+0\s+([\d.]+)\s+([\d.]+)')
        .firstMatch(dec(pdf))!;
    expect(double.parse(m.group(1)!), 100, reason: 'oriented width');
    expect(double.parse(m.group(2)!), 200, reason: 'oriented height');
  });

  test('metadata-clean: no personal/device info (author/producer/creator/date)',
      () async {
    final s = dec(await const PdfBuilder().build([page()]));
    // NOTE: the pdf package emits a fixed '% .../dart_pdf' tool-attribution
    // header comment (unsuppressible, non-personal — accepted, like /ID). We
    // assert only that PERSONAL/DEVICE metadata is absent.
    for (final marker in ['/Author', '/Producer', '/Creator', '/CreationDate']) {
      expect(s.contains(marker), isFalse, reason: 'metadata leak: $marker');
    }
  });

  test('seam: overlayFor invoked per page; text injected; none when image-only',
      () async {
    final spy = _SpyTextLayer(overlay: [pw.Text('SEAMTEXT')]);
    // compress:false so the (otherwise deflated) overlay text is greppable.
    final pdf = await PdfBuilder(textLayer: spy).build([page()], compress: false);
    expect(spy.calls.single.position, 1, reason: 'overlayFor called with the page');
    expect(dec(pdf).contains('SEAMTEXT'), isTrue, reason: 'injected text present');

    final imageOnly =
        await const PdfBuilder().build([page()], compress: false);
    expect(dec(imageOnly).contains('SEAMTEXT'), isFalse);
  });

  test('E2: uses displayPath — reads flat file when flatImagePath is set', () async {
    // imagePath points nowhere; only flatImagePath is readable.
    // If PdfBuilder uses imagePath it throws; if it uses displayPath it passes.
    final tmp = await Directory.systemTemp.createTemp('e2pdf');
    final flatFile = File('${tmp.path}/flat.jpg');
    await flatFile.writeAsBytes(jpeg); // reuse the fixture bytes
    final flatPage = PageImage(
      position: 1,
      imagePath: '/nonexistent/page_1.jpg',
      flatImagePath: flatFile.path,
    );
    final pdf = await const PdfBuilder().build([flatPage]);
    expect(pdf, isNotEmpty);
    await tmp.delete(recursive: true);
  });
}
