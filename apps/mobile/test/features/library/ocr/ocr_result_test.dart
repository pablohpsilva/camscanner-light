import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';

void main() {
  test('boxes round-trip through encode/decode', () {
    const r = OcrResult(
      text: 'HI',
      words: [OcrWordBox(text: 'HI', left: .1, top: .2, right: .3, bottom: .4)],
    );
    final decoded = OcrResult.decodeBoxes(r.encodeBoxes());
    expect(decoded, r.words);
  });

  test('decodeBoxes(null) and ("") return empty', () {
    expect(OcrResult.decodeBoxes(null), isEmpty);
    expect(OcrResult.decodeBoxes(''), isEmpty);
  });

  test('empty is blank text and no words', () {
    expect(OcrResult.empty.text, '');
    expect(OcrResult.empty.words, isEmpty);
    expect(OcrResult.empty.encodeBoxes(), '[]');
  });
}
