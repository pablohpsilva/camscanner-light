import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';

/// Device proof for fix(pdf): the searchable-PDF Unicode font must actually load
/// via rootBundle on a real device/simulator. If the asset weren't bundled,
/// loadOcrPdfFont() degrades to null and the .notdef box-with-X returns — so
/// this asserts the font resolves, i.e. the fix is live on-device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('OCR PDF Unicode font asset loads via rootBundle', (tester) async {
    final font = await loadOcrPdfFont();
    expect(
      font,
      isNotNull,
      reason: 'fonts/IBMPlexMono-Regular.ttf must be bundled + rootBundle-loadable',
    );
  });
}
