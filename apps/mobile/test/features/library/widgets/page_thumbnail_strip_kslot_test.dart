import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/page_thumbnail_strip.dart';

/// P13 kSlot-magic-number: the auto-scroll slot advance is DERIVED from the tile
/// geometry, not a hand-summed literal — so a tile-size tweak can't silently
/// break auto-scroll targeting.
void main() {
  test('kSlot is derived from the tile width + both margins', () {
    expect(kSlot, kTileWidth + 2 * kTileMargin);
  });

  test('the derived slot equals the previous hand-summed value (56 + 4 + 4)',
      () {
    expect(kSlot, 64.0);
  });
}
