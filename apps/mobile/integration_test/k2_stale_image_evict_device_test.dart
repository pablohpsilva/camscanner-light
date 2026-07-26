import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/image_cache_invalidator.dart';

/// Regression guard for "rotate only works once / Auto filter does nothing":
/// every page edit regenerates the display flat IN PLACE at the same path, so
/// the on-screen refresh depends ENTIRELY on the image cache being evicted for
/// the exact variant the viewer decodes — Image.file(..., cacheWidth: w), i.e.
/// a ResizeImage(FileImage, width: w) keyed by a private ResizeImageKey.
///
/// Runs the REAL dart:ui decode (native skia), so this must pass on device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Decode [provider] through the cache once and return the resulting image.
  Future<ui.Image> resolveOnce(ImageProvider provider) {
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.complete(info.image);
      },
      onError: (e, s) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Uint8List solidJpeg(int w, int h) =>
      Uint8List.fromList(img.encodeJpg(img.Image(width: w, height: h)));

  testWidgets(
    'same-path flat refreshes on screen only after the scoped evict',
    (tester) async {
      final dir = await Directory.systemTemp.createTemp('k2evict');
      final path = '${dir.path}/flat.jpg';
      const width = 32; // the viewer decodes at a bounded cacheWidth

      // v1: a landscape 40x20 base. Displayed variant = ResizeImage(width:32).
      File(path).writeAsBytesSync(solidJpeg(40, 20));
      final displayed = ResizeImage(FileImage(File(path)), width: width);

      final first = await resolveOnce(displayed);
      // width clamped to 32; aspect preserved (40x20 -> 32x16).
      expect(first.width, 32);
      expect(first.height, 16);

      // Edit regenerates the flat IN PLACE with new dimensions (like a rotate).
      // Keep it wider than cacheWidth so the ResizeImage downscales
      // deterministically (allowUpscaling defaults to false): 40x40 -> 32x32.
      File(path).writeAsBytesSync(solidJpeg(40, 40));

      // Without eviction the cache still serves v1 — the very staleness that
      // made rotate "work once". Assert it so the test proves the mechanism.
      final stale = await resolveOnce(
        ResizeImage(FileImage(File(path)), width: width),
      );
      expect(
        stale.width,
        32,
        reason: 'still v1 landscape from cache pre-evict',
      );
      expect(
        stale.height,
        16,
        reason: 'still v1 landscape from cache pre-evict',
      );

      // The production fix: evict the exact displayed variant.
      await const ScopedImageCacheInvalidator().evict(path, cacheWidth: width);

      final fresh = await resolveOnce(
        ResizeImage(FileImage(File(path)), width: width),
      );
      expect(fresh.width, 32, reason: 'v2 width clamped to 32');
      expect(
        fresh.height,
        32,
        reason: 'v2 (40x40) re-decoded fresh after evict — was 16 when stale',
      );

      await tester.pumpAndSettle();
      await dir.delete(recursive: true);
    },
  );
}
