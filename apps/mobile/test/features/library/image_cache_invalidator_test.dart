import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_cache_invalidator.dart';

/// P13 imagecache-clear-global: the scoped invalidator evicts EXACTLY the edited
/// page's providers and leaves every other cached image intact (the old code
/// wiped the whole cache on every edit).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = PaintingBinding.instance.imageCache;

  // A cache entry that stays pending forever — enough to occupy a cache slot.
  ImageStreamCompleter pending() =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);

  setUp(cache.clear);
  tearDown(cache.clear);

  test(
    'evicts the target FileImage + its ResizeImage variant, leaves others',
    () {
      final a = FileImage(File('/a.jpg'));
      final aResized = ResizeImage(FileImage(File('/a.jpg')), width: 100);
      final b = FileImage(File('/b.jpg'));
      cache.putIfAbsent(a, pending);
      cache.putIfAbsent(aResized, pending);
      cache.putIfAbsent(b, pending);

      const ScopedImageCacheInvalidator().evict('/a.jpg', cacheWidth: 100);

      expect(cache.statusForKey(a).untracked, isTrue, reason: 'base evicted');
      expect(
        cache.statusForKey(aResized).untracked,
        isTrue,
        reason: 'resized variant evicted',
      );
      expect(
        cache.statusForKey(b).untracked,
        isFalse,
        reason: 'an unrelated image survives (not a global clear)',
      );
    },
  );

  test('without a cacheWidth, evicts only the bare FileImage', () {
    final a = FileImage(File('/a.jpg'));
    cache.putIfAbsent(a, pending);
    const ScopedImageCacheInvalidator().evict('/a.jpg');
    expect(cache.statusForKey(a).untracked, isTrue);
  });
}
