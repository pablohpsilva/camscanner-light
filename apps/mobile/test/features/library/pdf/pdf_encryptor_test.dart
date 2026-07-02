import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/pdf/pdf_encryptor.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

String _ascii(List<int> b) {
  final s = StringBuffer();
  for (final c in b) {
    s.writeCharCode(c);
  }
  return s.toString();
}

void main() {
  Future<Uint8List> plainPdf() async {
    final doc = pw.Document();
    doc.addPage(pw.Page(build: (_) => pw.SizedBox()));
    return Uint8List.fromList(await doc.save());
  }

  test('encrypts a PDF with AES-256 and the given password', () async {
    final plain = await plainPdf();
    expect(_ascii(plain).contains('/Encrypt'), isFalse,
        reason: 'the plain PDF must not be encrypted');

    final enc = await const SyncfusionPdfEncryptor().encrypt(plain, 'secret');

    expect(_ascii(enc).contains('/Encrypt'), isTrue,
        reason: 'the output must be an encrypted PDF');
    // Reopens with the password (proves it is validly encrypted with it).
    final doc = sf.PdfDocument(inputBytes: enc, password: 'secret');
    expect(doc.pages.count, greaterThan(0));
    doc.dispose();
  });
}
