import 'dart:typed_data';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/image_warper.dart';

class _RecordingWarper implements ImageWarper {
  final String tag;
  final List<String> log;
  _RecordingWarper(this.tag, this.log);
  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async {
    log.add(tag);
    return Uint8List(0);
  }
}

void main() {
  late List<String> log;
  late HybridWarper warper;
  setUp(() {
    log = [];
    warper = HybridWarper(
      perspective: _RecordingWarper('perspective', log),
      coons: _RecordingWarper('coons', log),
    );
  });

  final bytes = Uint8List(0);

  test('fullFrame → null, neither warper invoked', () async {
    expect(await warper.warp(bytes, CropCorners.fullFrame), isNull);
    expect(log, isEmpty);
  });

  test('straight crop → perspective path', () async {
    const straight = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9));
    await warper.warp(bytes, straight);
    expect(log, ['perspective']);
  });

  test('bent crop → coons path', () async {
    const bent = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.1),
      bottomRight: Offset(0.9, 0.9), bottomLeft: Offset(0.1, 0.9),
      topMidDev: Offset(0, -0.05));
    await warper.warp(bytes, bent);
    expect(log, ['coons']);
  });
}
