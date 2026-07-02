import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;

/// Encrypts a generated PDF with a user password. Injectable (DIP) so the engine
/// is swappable and testable. Nothing leaves the device.
abstract interface class PdfEncryptor {
  Future<Uint8List> encrypt(Uint8List pdfBytes, String password);
}

/// Production encryptor backed by `syncfusion_flutter_pdf` (pure Dart). Loads the
/// generated PDF, applies AES-256 + the password (as both user and owner
/// password), clears document info for metadata hygiene, and re-saves.
class SyncfusionPdfEncryptor implements PdfEncryptor {
  const SyncfusionPdfEncryptor();

  @override
  Future<Uint8List> encrypt(Uint8List pdfBytes, String password) async {
    final doc = sf.PdfDocument(inputBytes: pdfBytes);
    try {
      doc.security.userPassword = password;
      doc.security.ownerPassword = password;
      doc.security.algorithm = sf.PdfEncryptionAlgorithm.aesx256Bit;
      final info = doc.documentInformation;
      info.author = '';
      info.creator = '';
      info.producer = '';
      info.title = '';
      info.subject = '';
      info.keywords = '';
      return Uint8List.fromList(await doc.save());
    } finally {
      doc.dispose();
    }
  }
}
