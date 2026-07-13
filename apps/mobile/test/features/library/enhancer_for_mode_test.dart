import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/enhancer_for_mode.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';

void main() {
  test('enhancerForMode maps every mode to its enhancer', () {
    expect(enhancerForMode(EnhancerMode.none), isA<NoneEnhancer>());
    expect(enhancerForMode(EnhancerMode.grayscale), isA<GrayscaleEnhancer>());
    expect(enhancerForMode(EnhancerMode.auto), isA<AutoEnhancer>());
    expect(enhancerForMode(EnhancerMode.color), isA<ColorEnhancer>());
  });
}
