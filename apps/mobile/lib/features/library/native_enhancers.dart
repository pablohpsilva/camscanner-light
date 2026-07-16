import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'auto_enhancer.dart'
    show kAutoProxyLongSide, kAutoDilateRadius, kAutoBlurRadius, kAutoMaxGain;
import 'white_point_lut.dart';

/// Native (dartcv) filter kernels — the isolate-side mirror of the Dart
/// `*_enhancer` modules, split out of the `NativePageProcessor` god-file (P08).
/// Each is a top-level, isolate-sendable function that OWNS its intermediate
/// Mats and disposes them in a `finally` (the same discipline as
/// `opencv_edge_detector.dart._segmentGray`, the reference standard). The math
/// is moved verbatim — device auto-enhance parity is unchanged.

/// Per-channel flat-field + white-point finish — the native mirror of
/// `autoEnhanceOriented` in auto_enhancer.dart, using the same constants.
/// Input [src] is a BGR CV_8UC3 Mat (OpenCV native order). Returns a new
/// CV_8UC3 BGR Mat owned by the caller.
cv.Mat autoFlatField(cv.Mat src) {
  final rows = src.rows, cols = src.cols;
  // Explicit kernel size matches Dart's img.gaussianBlur(radius: kAutoBlurRadius)
  // which uses a (2*radius+1) × (2*radius+1) kernel with sigma = radius*(2/3).
  final blurKernel = 2 * kAutoBlurRadius + 1;
  final blurSigma = kAutoBlurRadius * 2.0 / 3.0;

  cv.Mat? proxy,
      kernel,
      dilated,
      blurred,
      bg,
      bgF,
      bgFloored,
      floorMat,
      srcF,
      flatF,
      flat,
      lut;
  try {
    // 1. Background estimate: resize to proxy → dilate(15×15) → blur.
    final longest = cols > rows ? cols : rows;
    final scale = longest > kAutoProxyLongSide
        ? kAutoProxyLongSide / longest
        : 1.0;
    final pw = (cols * scale).round().clamp(1, cols);
    final ph = (rows * scale).round().clamp(1, rows);
    proxy = cv.resize(src, (pw, ph), interpolation: cv.INTER_AREA);
    final k = 2 * kAutoDilateRadius + 1; // 15
    kernel = cv.getStructuringElement(cv.MORPH_RECT, (k, k));
    dilated = cv.dilate(proxy, kernel);
    // Exact match to Dart: same kernel size and sigma derived from radius.
    blurred = cv.gaussianBlur(dilated, (blurKernel, blurKernel), blurSigma);
    bg = cv.resize(blurred, (cols, rows), interpolation: cv.INTER_LINEAR);

    // 2. Flatten: px*255 / max(bg, 255/maxGain) on float Mats (no truncation).
    final floorVal = 255.0 / kAutoMaxGain; // 42.5
    bgF = bg.convertTo(cv.MatType.CV_32FC3);
    floorMat = cv.Mat.fromScalar(
      rows,
      cols,
      cv.MatType.CV_32FC3,
      cv.Scalar.all(floorVal),
    );
    bgFloored = cv.max(bgF, floorMat);
    srcF = src.convertTo(cv.MatType.CV_32FC3);
    flatF = cv.divide(srcF, bgFloored, scale: 255); // srcF*255/bgFloored
    flat = flatF.convertTo(cv.MatType.CV_8UC3); // saturate to [0,255]

    // 3. White-point stretch via per-channel 3-channel LUT (BGR).
    lut = whitePointLut3(flat);
    return cv.LUT(flat, lut);
  } finally {
    for (final m in [
      proxy,
      kernel,
      dilated,
      blurred,
      bg,
      bgF,
      bgFloored,
      floorMat,
      srcF,
      flatF,
      flat,
      lut,
    ]) {
      m?.dispose();
    }
  }
}

/// Builds a 1×256 CV_8UC3 LUT reproducing auto_enhancer.dart's per-channel
/// white-point stretch (kAutoWhiteClip clip, kAutoBlackAnchor, linear). Reads
/// the flattened Mat's raw BGR bytes to build histograms per channel (B/G/R),
/// delegates the pure table math to [whitePointLut3Table] (host-tested, P08),
/// then wraps the 768-element table in a disposable LUT Mat for use with
/// [cv.LUT].
cv.Mat whitePointLut3(cv.Mat flat) {
  final data = flat.data; // interleaved BGR bytes: rows*cols*3
  final hist = [
    List<int>.filled(256, 0), // B
    List<int>.filled(256, 0), // G
    List<int>.filled(256, 0), // R
  ];
  for (var i = 0; i < data.length; i += 3) {
    hist[0][data[i]]++;
    hist[1][data[i + 1]]++;
    hist[2][data[i + 2]]++;
  }
  final lut = whitePointLut3Table(hist);
  return cv.Mat.fromList(1, 256, cv.MatType.CV_8UC3, lut);
}

/// Contrast 1.1 + brightness 1.05 via a 1×256 CV_8UC1 LUT applied to every
/// channel: v' = clamp((v−128)*1.1 + 128, then *1.05, 0..255).
/// The intermediate LUT Mat is disposed before returning.
cv.Mat colorBoost(cv.Mat src) {
  final lut = List<int>.filled(256, 0);
  for (var v = 0; v < 256; v++) {
    final c = (v - 128) * 1.1 + 128;
    lut[v] = (c * 1.05).round().clamp(0, 255);
  }
  cv.Mat? lutMat;
  try {
    lutMat = cv.Mat.fromList(1, 256, cv.MatType.CV_8UC1, lut);
    return cv.LUT(src, lutMat); // 1-ch LUT applies to every channel
  } finally {
    lutMat?.dispose();
  }
}

/// Luminance grayscale, re-expanded to 3 channels so the JPEG encoder sees BGR.
/// The intermediate gray Mat is disposed before returning.
cv.Mat grayscale(cv.Mat src) {
  cv.Mat? gray;
  try {
    gray = cv.cvtColor(src, cv.COLOR_BGR2GRAY);
    return cv.cvtColor(gray, cv.COLOR_GRAY2BGR);
  } finally {
    gray?.dispose();
  }
}
