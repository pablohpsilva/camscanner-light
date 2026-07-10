import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/fallback_page_processor.dart';
import 'package:mobile/features/library/page_processor.dart';

class _Fake implements PageProcessor {
  _Fake(this._result, {this.throws = false});
  final Uint8List? _result;
  final bool throws;
  int calls = 0;
  @override
  Future<Uint8List?> process(Uint8List b, CropCorners c, EnhancerMode m) async {
    calls++;
    if (throws) throw Exception('boom');
    return _result;
  }
}

final _bytes = Uint8List.fromList([1, 2, 3]);
const _crop = CropCorners(
  topLeft: Offset(0.1, 0.1),
  topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9),
  bottomLeft: Offset(0.1, 0.9),
);

void main() {
  test(
    'none + fullFrame short-circuits: neither engine called, returns null',
    () async {
      final primary = _Fake(Uint8List.fromList([9]));
      final fallback = _Fake(Uint8List.fromList([8]));
      final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
      final out = await fp.process(
        _bytes,
        CropCorners.fullFrame,
        EnhancerMode.none,
      );
      expect(out, isNull);
      expect(primary.calls, 0);
      expect(fallback.calls, 0);
    },
  );

  test('primary succeeds → fallback not called', () async {
    final primary = _Fake(Uint8List.fromList([9]));
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [9]);
    expect(fallback.calls, 0);
  });

  test('primary returns null (failure) → fallback runs', () async {
    final primary = _Fake(null);
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [8]);
    expect(primary.calls, 1);
    expect(fallback.calls, 1);
  });

  test('primary throws → fallback runs', () async {
    final primary = _Fake(null, throws: true);
    final fallback = _Fake(Uint8List.fromList([8]));
    final fp = FallbackPageProcessor(primary: primary, fallback: fallback);
    final out = await fp.process(_bytes, _crop, EnhancerMode.auto);
    expect(out, [8]);
    expect(fallback.calls, 1);
  });
}
