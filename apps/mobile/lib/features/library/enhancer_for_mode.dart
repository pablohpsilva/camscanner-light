import 'auto_enhancer.dart';
import 'color_enhancer.dart';
import 'enhancer_mode.dart';
import 'grayscale_enhancer.dart';
import 'image_enhancer.dart';

/// The concrete [ImageEnhancer] for an [EnhancerMode]. Single source of truth
/// for the mode → enhancer mapping (used by the scan-review and page-editor
/// filter pickers). Inverse of `enhancerModeOf` in warp_enhancer.dart.
ImageEnhancer enhancerForMode(EnhancerMode mode) => switch (mode) {
  EnhancerMode.none => const NoneEnhancer(),
  EnhancerMode.grayscale => const GrayscaleEnhancer(),
  EnhancerMode.auto => const AutoEnhancer(),
  EnhancerMode.color => const ColorEnhancer(),
};
