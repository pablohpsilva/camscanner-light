import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';

/// Resolves the EXIF-applied natural size of the image at [path] (P07: the one
/// shared copy — this was duplicated verbatim in `capture_review_screen` and
/// `edit_crop_screen`). Uses the framework's [FileImage] decoder, which bakes
/// the Orientation tag, so the returned [Size] matches the displayed image.
/// The future completes with an error (it does NOT hang) if the file cannot be
/// decoded — callers inject a stub in host tests to avoid a real decode.
Future<Size> resolveImageSize(String path) {
  final completer = Completer<Size>();
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
      }
      stream.removeListener(listener);
    },
    onError: (e, st) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}
