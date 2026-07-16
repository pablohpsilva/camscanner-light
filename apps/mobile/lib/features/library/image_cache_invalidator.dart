import 'dart:io';

import 'package:flutter/painting.dart';

/// Evicts a SINGLE image path from the global image cache (P13
/// imagecache-clear-global) — the scoped replacement for the page viewer's old
/// wholesale `imageCache.clear()` + `clearLiveImages()`, which evicted every
/// cached image app-wide on every edit. Injectable so tests inject a spy.
abstract interface class ImageCacheInvalidator {
  /// Evicts the cache entry for [path]'s `FileImage` and, when [cacheWidth] is
  /// given, its `ResizeImage(width)` variant — so a same-path regenerated flat
  /// re-decodes fresh while every OTHER cached image (thumbnails, other screens)
  /// survives.
  void evict(String path, {int? cacheWidth});
}

/// Production [ImageCacheInvalidator]: scoped eviction against the global
/// [PaintingBinding] image cache.
class ScopedImageCacheInvalidator implements ImageCacheInvalidator {
  const ScopedImageCacheInvalidator();

  @override
  void evict(String path, {int? cacheWidth}) {
    final cache = PaintingBinding.instance.imageCache;
    final base = FileImage(File(path));
    // The fit-to-screen view decodes via ResizeImage(base, width: cacheWidth);
    // a zoomed full-res view decodes the bare FileImage. Evict whichever exist.
    cache.evict(base);
    if (cacheWidth != null) {
      cache.evict(ResizeImage(base, width: cacheWidth));
    }
  }
}
