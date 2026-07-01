import 'dart:convert';

/// One recognized word and its box, normalized to the page image (0..1).
class OcrWordBox {
  final String text;
  final double left, top, right, bottom;
  const OcrWordBox({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  Map<String, dynamic> toJson() =>
      {'t': text, 'l': left, 'o': top, 'r': right, 'b': bottom};

  factory OcrWordBox.fromJson(Map<String, dynamic> j) => OcrWordBox(
        text: j['t'] as String,
        left: (j['l'] as num).toDouble(),
        top: (j['o'] as num).toDouble(),
        right: (j['r'] as num).toDouble(),
        bottom: (j['b'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is OcrWordBox &&
      other.text == text &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(text, left, top, right, bottom);
}

/// A page's recognized text and word boxes.
class OcrResult {
  final String text;
  final List<OcrWordBox> words;
  const OcrResult({required this.text, this.words = const []});

  static const empty = OcrResult(text: '', words: []);

  String encodeBoxes() =>
      jsonEncode(words.map((w) => w.toJson()).toList());

  static List<OcrWordBox> decodeBoxes(String? json) {
    if (json == null || json.isEmpty) return const [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => OcrWordBox.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
