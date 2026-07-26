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
  /// survives. Async because deriving a provider's cache key goes through
  /// [ImageProvider.obtainKey]; await it before re-decoding the same path.
  Future<void> evict(String path, {int? cacheWidth});
}

/// Production [ImageCacheInvalidator]: scoped eviction against the global
/// [PaintingBinding] image cache.
class ScopedImageCacheInvalidator implements ImageCacheInvalidator {
  const ScopedImageCacheInvalidator();

  @override
  Future<void> evict(String path, {int? cacheWidth}) async {
    final base = FileImage(File(path));
    // The fit-to-screen view decodes via ResizeImage(base, width: cacheWidth);
    // a zoomed full-res view decodes the bare FileImage. Evict whichever exist.
    //
    // Use each provider's own evict() (which resolves the REAL cache key via
    // obtainKey) — NOT cache.evict(provider). A ResizeImage is cached under a
    // private ResizeImageKey, so passing the ResizeImage object as the key
    // matches nothing and silently no-ops, leaving the displayed (resized) flat
    // stale after every same-path edit → "rotate only works once".
    await base.evict();
    if (cacheWidth != null) {
      await ResizeImage(base, width: cacheWidth).evict();
    }
  }
}
