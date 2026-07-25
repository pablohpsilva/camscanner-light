import 'package:opencv_dart/opencv_dart.dart' as cv;

import 'auto_enhancer.dart'
    show
        kAutoProxyLongSide,
        kAutoDilateRadius,
        kAutoBlurRadius,
        kAutoMaxGain,
        kAutoLocalWindowRadius,
        kAutoLocalBlurRadius,
        kAutoLocalSpanLo,
        kAutoLocalSpanHi,
        kAutoLocalStrength;

/// Native (dartcv) filter kernels — the isolate-side mirror of the Dart
/// `*_enhancer` modules, split out of the `NativePageProcessor` god-file (P08).
/// Each is a top-level, isolate-sendable function that OWNS its intermediate
/// Mats and disposes them in a `finally` (the same discipline as
/// `opencv_edge_detector.dart._segmentGray`, the reference standard). The math
/// is moved verbatim — device auto-enhance parity is unchanged.

/// Per-channel flat-field + local-contrast finish — the native mirror of
/// `autoEnhanceOriented` in auto_enhancer.dart, using the same constants.
/// Input [src] is a BGR CV_8UC3 Mat (OpenCV native order). Returns a new
/// CV_8UC3 BGR Mat owned by the caller.
cv.Mat autoFlatField(cv.Mat src) {
  final rows = src.rows, cols = src.cols;
  // Explicit kernel size matches Dart's img.gaussianBlur(radius: kAutoBlurRadius)
  // which uses a (2*radius+1) × (2*radius+1) kernel with sigma = radius*(2/3).
  final blurKernel = 2 * kAutoBlurRadius + 1;
  final blurSigma = kAutoBlurRadius * 2.0 / 3.0;

  // Every intermediate below is disposed as soon as it is no longer needed
  // (not just in the trailing `finally`): stage 3 allocates many
  // full-resolution float Mats, and letting them all stay alive until the
  // function returns pushes peak memory high enough to OOM-crash on large
  // (near-cap) captures — confirmed on-device via the np2 over-cap case.
  // `finally` remains a safety net for the exception path only: on the happy
  // path every one of these is already null by the time it runs.
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
      gray,
      grayProxy,
      localKernel,
      blackP,
      whiteP,
      blackPB,
      whitePB,
      blackResized,
      blackF,
      whiteResized,
      whiteF,
      grayF,
      spanF,
      oneScalar,
      guardLin,
      guardTrunc,
      guardF,
      effF,
      spanSafe,
      ynum,
      yprimeRaw,
      yTrunc,
      yprime,
      diff,
      blendTerm,
      blended,
      graySafe,
      ratio,
      ratio3,
      flatF2,
      outF;
  cv.VecMat? ratioVec;
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
    proxy.dispose();
    proxy = null;
    kernel.dispose();
    kernel = null;
    // Exact match to Dart: same kernel size and sigma derived from radius.
    blurred = cv.gaussianBlur(dilated, (blurKernel, blurKernel), blurSigma);
    dilated.dispose();
    dilated = null;
    bg = cv.resize(blurred, (cols, rows), interpolation: cv.INTER_LINEAR);
    blurred.dispose();
    blurred = null;

    // 2. Flatten: px*255 / max(bg, 255/maxGain) on float Mats (no truncation).
    final floorVal = 255.0 / kAutoMaxGain; // 42.5
    bgF = bg.convertTo(cv.MatType.CV_32FC3);
    bg.dispose();
    bg = null;
    floorMat = cv.Mat.fromScalar(
      rows,
      cols,
      cv.MatType.CV_32FC3,
      cv.Scalar.all(floorVal),
    );
    bgFloored = cv.max(bgF, floorMat);
    bgF.dispose();
    bgF = null;
    floorMat.dispose();
    floorMat = null;
    srcF = src.convertTo(cv.MatType.CV_32FC3);
    flatF = cv.divide(srcF, bgFloored, scale: 255); // srcF*255/bgFloored
    srcF.dispose();
    srcF = null;
    bgFloored.dispose();
    bgFloored = null;
    flat = flatF.convertTo(cv.MatType.CV_8UC3); // saturate to [0,255]
    flatF.dispose();
    flatF = null;
    // `flat` is needed again at the very end (step 3's colour scale), kept.

    // 3. Local luminance contrast, colour preserved. Build local black (erode)
    //    and white (dilate) luma refs on a proxy, blur, upsample, then per-pixel
    //    apply a SMOOTH guard: yout = Y + strength*guard*(Y'-Y), where
    //    guard = clamp((span-lo)/(hi-lo), 0, 1) and Y' = clamp((Y-B)*255/span,
    //    0, 255). Scale BGR by yout/Y. Formula mirrors auto_enhancer.dart
    //    _localContrast (smooth-guard version).
    gray = cv.cvtColor(flat, cv.COLOR_BGR2GRAY); // CV_8UC1 luma
    grayProxy = cv.resize(gray, (pw, ph), interpolation: cv.INTER_AREA);
    final lwin = 2 * kAutoLocalWindowRadius + 1;
    localKernel = cv.getStructuringElement(cv.MORPH_RECT, (lwin, lwin));
    // BORDER_REPLICATE matches auto_enhancer.dart's _minFilter/_maxFilter1,
    // which clamp the window to valid indices at the edges (mathematically
    // identical to replicate-padding for a min/max filter). The library's
    // erode/dilate default to BORDER_CONSTANT with an all-zero border value
    // (not OpenCV's morphology-neutral +-DBL_MAX sentinel), which corrupts
    // the border strip if left at the default — verified via the np2
    // bright-bg parity case (border-region mean error dropped to ~0.02).
    blackP = cv.erode(grayProxy, localKernel, borderType: cv.BORDER_REPLICATE);
    whiteP = cv.dilate(grayProxy, localKernel, borderType: cv.BORDER_REPLICATE);
    grayProxy.dispose();
    grayProxy = null;
    localKernel.dispose();
    localKernel = null;
    final lblurK = 2 * kAutoLocalBlurRadius + 1;
    final lblurS = kAutoLocalBlurRadius * 2.0 / 3.0;
    blackPB = cv.gaussianBlur(blackP, (lblurK, lblurK), lblurS);
    blackP.dispose();
    blackP = null;
    whitePB = cv.gaussianBlur(whiteP, (lblurK, lblurK), lblurS);
    whiteP.dispose();
    whiteP = null;
    blackResized = cv.resize(blackPB, (
      cols,
      rows,
    ), interpolation: cv.INTER_LINEAR);
    blackPB.dispose();
    blackPB = null;
    blackF = blackResized.convertTo(cv.MatType.CV_32FC1);
    blackResized.dispose();
    blackResized = null;
    whiteResized = cv.resize(whitePB, (
      cols,
      rows,
    ), interpolation: cv.INTER_LINEAR);
    whitePB.dispose();
    whitePB = null;
    whiteF = whiteResized.convertTo(cv.MatType.CV_32FC1);
    whiteResized.dispose();
    whiteResized = null;
    grayF = gray.convertTo(cv.MatType.CV_32FC1);
    gray.dispose();
    gray = null;

    spanF = cv.subtract(whiteF, blackF); // W - B
    whiteF.dispose();
    whiteF = null;
    oneScalar = cv.Mat.fromScalar(
      rows,
      cols,
      cv.MatType.CV_32FC1,
      cv.Scalar.all(1),
    );

    // guard = clamp((span - lo) / (hi - lo), 0, 1). The linear part is folded
    // into a single convertTo (alpha/beta) so no extra full-size scalar Mats
    // are allocated; the [0,1] clamp uses threshold (TRUNC caps at 1, TOZERO
    // floors at 0), same allocation-free trick as the yPrime clamp below.
    final gLo = kAutoLocalSpanLo.toDouble();
    final gHi = kAutoLocalSpanHi.toDouble();
    final gScale = 1.0 / (gHi - gLo);
    guardLin = spanF.convertTo(
      cv.MatType.CV_32FC1,
      alpha: gScale,
      beta: -gLo * gScale,
    );
    guardTrunc = cv.threshold(guardLin, 1, 1, cv.THRESH_TRUNC).$2; // cap at 1
    guardLin.dispose();
    guardLin = null;
    guardF = cv.threshold(guardTrunc, 0, 0, cv.THRESH_TOZERO).$2; // floor at 0
    guardTrunc.dispose();
    guardTrunc = null;
    // effF = guard * strength (fold the scalar into convertTo).
    effF = guardF.convertTo(cv.MatType.CV_32FC1, alpha: kAutoLocalStrength);
    guardF.dispose();
    guardF = null;

    spanSafe = cv.max(spanF, oneScalar); // avoid divide-by-zero
    spanF.dispose();
    spanF = null;
    // yPrime = clamp((Y - B) * 255 / max(span, 1), 0, 255)
    ynum = cv.subtract(grayF, blackF);
    blackF.dispose();
    blackF = null;
    yprimeRaw = cv.divide(ynum, spanSafe, scale: 255);
    ynum.dispose();
    ynum = null;
    spanSafe.dispose();
    spanSafe = null;
    // Clamp to [0, 255] via threshold (no extra full-size scalar Mats):
    // TRUNC caps the top, TOZERO floors the bottom.
    yTrunc = cv.threshold(yprimeRaw, 255, 255, cv.THRESH_TRUNC).$2;
    yprimeRaw.dispose();
    yprimeRaw = null;
    yprime = cv.threshold(yTrunc, 0, 0, cv.THRESH_TOZERO).$2;
    yTrunc.dispose();
    yTrunc = null;

    // blended = Y + effF ⊙ (yPrime - Y), where effF = strength*guard.
    diff = cv.subtract(yprime, grayF);
    yprime.dispose();
    yprime = null;
    blendTerm = cv.multiply(effF, diff);
    effF.dispose();
    effF = null;
    diff.dispose();
    diff = null;
    blended = cv.add(grayF, blendTerm);
    blendTerm.dispose();
    blendTerm = null;

    // scale = blended / max(Y, 1); apply to each colour channel.
    graySafe = cv.max(grayF, oneScalar);
    grayF.dispose();
    grayF = null;
    oneScalar.dispose();
    oneScalar = null;
    ratio = cv.divide(blended, graySafe); // CV_32FC1
    blended.dispose();
    blended = null;
    graySafe.dispose();
    graySafe = null;
    ratioVec = [ratio, ratio, ratio].cvd;
    ratio3 = cv.merge(ratioVec); // CV_32FC3
    ratio.dispose();
    ratio = null;
    ratioVec.dispose();
    ratioVec = null;
    flatF2 = flat.convertTo(cv.MatType.CV_32FC3);
    flat.dispose();
    flat = null;
    outF = cv.multiply(flatF2, ratio3);
    flatF2.dispose();
    flatF2 = null;
    ratio3.dispose();
    ratio3 = null;
    final result = outF.convertTo(cv.MatType.CV_8UC3); // saturating cast
    outF.dispose();
    outF = null;
    return result;
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
      gray,
      grayProxy,
      localKernel,
      blackP,
      whiteP,
      blackPB,
      whitePB,
      blackResized,
      blackF,
      whiteResized,
      whiteF,
      grayF,
      spanF,
      oneScalar,
      guardLin,
      guardTrunc,
      guardF,
      effF,
      spanSafe,
      ynum,
      yprimeRaw,
      yTrunc,
      yprime,
      diff,
      blendTerm,
      blended,
      graySafe,
      ratio,
      ratio3,
      flatF2,
      outF,
    ]) {
      m?.dispose();
    }
    ratioVec?.dispose();
  }
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
