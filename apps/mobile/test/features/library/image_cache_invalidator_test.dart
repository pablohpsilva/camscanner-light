import 'dart:async';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_cache_invalidator.dart';

/// P13 imagecache-clear-global: the scoped invalidator evicts EXACTLY the edited
/// page's providers and leaves every other cached image intact (the old code
/// wiped the whole cache on every edit).
///
/// Entries are inserted under the SAME cache key production uses — the one the
/// framework derives via [ImageProvider.obtainKey]. For a [ResizeImage] that key
/// is a private `ResizeImageKey`, NOT the provider object itself, so a test that
/// keys by the provider would be self-consistent but green against the real
/// "rotate only works once" bug. Always insert/query by the obtained key.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final cache = PaintingBinding.instance.imageCache;

  // A cache entry that stays pending forever — enough to occupy a cache slot.
  ImageStreamCompleter pending() =>
      OneFrameImageStreamCompleter(Completer<ImageInfo>().future);

  // The real cache key for [provider], as Image.file/ResizeImage resolve it.
  Future<Object> keyFor(ImageProvider provider) =>
      provider.obtainKey(ImageConfiguration.empty);

  setUp(cache.clear);
  tearDown(cache.clear);

  test(
    'evicts the target FileImage + its ResizeImage variant, leaves others',
    () async {
      // The page viewer decodes every display image via
      // Image.file(..., cacheWidth: w) => ResizeImage(FileImage, width: w),
      // whose cache key is derived through obtainKey (a ResizeImageKey).
      final aKey = await keyFor(FileImage(File('/a.jpg')));
      final aResizedKey = await keyFor(
        ResizeImage(FileImage(File('/a.jpg')), width: 100),
      );
      final bKey = await keyFor(FileImage(File('/b.jpg')));
      cache.putIfAbsent(aKey, pending);
      cache.putIfAbsent(aResizedKey, pending);
      cache.putIfAbsent(bKey, pending);

      await const ScopedImageCacheInvalidator().evict(
        '/a.jpg',
        cacheWidth: 100,
      );

      expect(
        cache.statusForKey(aKey).untracked,
        isTrue,
        reason: 'base evicted',
      );
      expect(
        cache.statusForKey(aResizedKey).untracked,
        isTrue,
        reason: 'resized variant (the one actually displayed) evicted',
      );
      expect(
        cache.statusForKey(bKey).untracked,
        isFalse,
        reason: 'an unrelated image survives (not a global clear)',
      );
    },
  );

  test('without a cacheWidth, evicts only the bare FileImage', () async {
    final aKey = await keyFor(FileImage(File('/a.jpg')));
    cache.putIfAbsent(aKey, pending);
    await const ScopedImageCacheInvalidator().evict('/a.jpg');
    expect(cache.statusForKey(aKey).untracked, isTrue);
  });
}
