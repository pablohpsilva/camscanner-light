import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/ocr/channel_ocr_engine.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';

/// Host tests for the platform-channel OCR engine. Native OCR (Apple Vision on
/// iOS, ML Kit via Kotlin on Android) runs behind a single MethodChannel; each
/// native side returns text + word boxes ALREADY normalized 0..1 with a
/// top-left origin, matching [OcrWordBox]. These tests pin the Dart mapping,
/// clamping, and error handling with a mocked channel — no native code needed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('camscanner/ocr');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  final jpeg = Uint8List.fromList([1, 2, 3, 4]);

  void mock(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('invokes recognize with the jpeg bytes', () async {
    MethodCall? seen;
    mock((call) async {
      seen = call;
      return {'text': '', 'words': <Object?>[]};
    });

    await const ChannelOcrEngine().recognize(jpeg);

    expect(seen?.method, 'recognize');
    expect((seen?.arguments as Map)['jpeg'], jpeg);
  });

  test('maps text and normalized top-left word boxes to OcrResult', () async {
    mock((call) async => {
          'text': 'ACME Corp',
          'words': [
            {'text': 'ACME', 'left': 0.1, 'top': 0.2, 'right': 0.3, 'bottom': 0.25},
            {'text': 'Corp', 'left': 0.35, 'top': 0.2, 'right': 0.5, 'bottom': 0.25},
          ],
        });

    final result = await const ChannelOcrEngine().recognize(jpeg);

    expect(result.text, 'ACME Corp');
    expect(result.words, [
      const OcrWordBox(text: 'ACME', left: 0.1, top: 0.2, right: 0.3, bottom: 0.25),
      const OcrWordBox(text: 'Corp', left: 0.35, top: 0.2, right: 0.5, bottom: 0.25),
    ]);
  });

  test('clamps out-of-range coordinates into 0..1', () async {
    mock((call) async => {
          'text': 'x',
          'words': [
            {'text': 'x', 'left': -0.1, 'top': 1.4, 'right': 1.2, 'bottom': -0.3},
          ],
        });

    final w = (await const ChannelOcrEngine().recognize(jpeg)).words.single;

    expect(w.left, 0.0);
    expect(w.top, 1.0);
    expect(w.right, 1.0);
    expect(w.bottom, 0.0);
  });

  test('textless image → empty result, never throws', () async {
    mock((call) async => {'text': '', 'words': <Object?>[]});

    final result = await const ChannelOcrEngine().recognize(jpeg);

    expect(result.text, '');
    expect(result.words, isEmpty);
  });

  test('platform failure degrades to empty (contract: must not throw)',
      () async {
    mock((call) async => throw PlatformException(code: 'ERR'));

    final result = await const ChannelOcrEngine().recognize(jpeg);

    expect(result.text, '');
    expect(result.words, isEmpty);
  });

  test('missing native handler degrades to empty', () async {
    // No mock handler registered → MissingPluginException.
    final result = await const ChannelOcrEngine().recognize(jpeg);

    expect(result.text, '');
    expect(result.words, isEmpty);
  });
}
