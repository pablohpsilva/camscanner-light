import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/bilinear_sampler.dart';

/// P09 Task 2: the perspective and Coons warpers shared a line-for-line
/// inverse-bilinear inner loop (clamp → 4-tap → 3-ch interp → round); only the
/// per-pixel source-coordinate mapper differed. sampleBilinearInto is that one
/// shared loop; the mapper is injected. These host tests lock its contract.
void main() {
  test('identity integer map copies the source pixel-for-pixel', () {
    final src = Uint8List.fromList([
      10, 20, 30, 40, 50, 60, // row 0: (0,0),(1,0)
      70, 80, 90, 100, 110, 120, // row 1: (0,1),(1,1)
    ]);
    final out = Uint8List(2 * 2 * 3);
    sampleBilinearInto(
      out: out,
      srcBuf: src,
      sw: 2,
      sh: 2,
      outW: 2,
      outH: 2,
      mapToSrc: (dx, dy) => Offset(dx.toDouble(), dy.toDouble()),
    );
    expect(out, src);
  });

  test('a half-pixel map bilinearly interpolates the two neighbours', () {
    // 2x1 source: black then white; sampling x=0.5 gives the midpoint (50).
    final src = Uint8List.fromList([0, 0, 0, 100, 100, 100]);
    final out = Uint8List(3);
    sampleBilinearInto(
      out: out,
      srcBuf: src,
      sw: 2,
      sh: 1,
      outW: 1,
      outH: 1,
      mapToSrc: (_, _) => const Offset(0.5, 0.0),
    );
    expect(out[0], 50);
    expect(out[1], 50);
    expect(out[2], 50);
  });

  test('coords past the edge clamp to the last row/column', () {
    final src = Uint8List.fromList([0, 0, 0, 100, 100, 100]);
    final out = Uint8List(3);
    sampleBilinearInto(
      out: out,
      srcBuf: src,
      sw: 2,
      sh: 1,
      outW: 1,
      outH: 1,
      mapToSrc: (_, _) => const Offset(99, 99), // clamps to xMax=1, yMax=0
    );
    expect(out[0], 100);
    expect(out[1], 100);
    expect(out[2], 100);
  });

  test('negative coords clamp to the first row/column', () {
    final src = Uint8List.fromList([7, 8, 9, 100, 100, 100]);
    final out = Uint8List(3);
    sampleBilinearInto(
      out: out,
      srcBuf: src,
      sw: 2,
      sh: 1,
      outW: 1,
      outH: 1,
      mapToSrc: (_, _) => const Offset(-5, -5),
    );
    expect(out[0], 7);
    expect(out[1], 8);
    expect(out[2], 9);
  });

  test('the mapper is called once per output pixel, row-major', () {
    final calls = <(int, int)>[];
    final out = Uint8List(3 * 2 * 3);
    sampleBilinearInto(
      out: out,
      srcBuf: Uint8List.fromList([1, 2, 3]),
      sw: 1,
      sh: 1,
      outW: 3,
      outH: 2,
      mapToSrc: (dx, dy) {
        calls.add((dx, dy));
        return Offset.zero;
      },
    );
    expect(calls, [(0, 0), (1, 0), (2, 0), (0, 1), (1, 1), (2, 1)]);
  });
}
