import 'dart:typed_data';

/// DIP boundary for post-capture image enhancement. Parallel to [ImageWarper].
/// Each filter is its own const-constructible strategy (OCP: add filters by
/// adding classes, never by modifying this file).
abstract interface class ImageEnhancer {
  /// Returns enhanced JPEG bytes. Never throws — on any failure returns
  /// [bytes] unchanged.
  Future<Uint8List> enhance(Uint8List bytes);
}

/// Pass-through: returns [bytes] unchanged. Default when no filter is chosen.
class NoneEnhancer implements ImageEnhancer {
  const NoneEnhancer();

  @override
  Future<Uint8List> enhance(Uint8List bytes) async => bytes;
}
