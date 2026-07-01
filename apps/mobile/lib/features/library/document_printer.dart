import 'dart:io';

import 'package:printing/printing.dart';

/// Sends a PDF to the OS print sheet (print / save-as-PDF / AirPrint). Injectable
/// (DIP) so tests and the on-device BDD use a no-op fake instead of the native
/// print UI (which cannot be driven by an automated test).
abstract interface class DocumentPrinter {
  Future<void> printPdf(File pdf, {required String name});
}

/// Production printer backed by the `printing` package. Reads the PDF bytes and
/// hands them to the platform print sheet. Nothing leaves the device except via
/// the user's chosen printer/destination.
class SystemDocumentPrinter implements DocumentPrinter {
  const SystemDocumentPrinter();

  @override
  Future<void> printPdf(File pdf, {required String name}) async {
    await Printing.layoutPdf(
      name: name,
      onLayout: (_) async => pdf.readAsBytes(),
    );
  }
}
