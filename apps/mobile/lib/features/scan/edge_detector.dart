import 'dart:typed_data';

import '../library/crop_corners.dart';

/// Immutable detection result: four corners in normalized [0..1] display
/// coordinates and a confidence score in [0.0, 1.0].
class DetectionResult {
  final CropCorners corners;
  final double confidence;
  const DetectionResult({required this.corners, required this.confidence});

  @override
  bool operator ==(Object other) =>
      other is DetectionResult &&
      corners == other.corners &&
      confidence == other.confidence;

  @override
  int get hashCode => Object.hash(corners, confidence);

  @override
  String toString() =>
      'DetectionResult(corners: $corners, confidence: $confidence)';
}

/// DIP boundary for document-edge detection. Concrete engine is injected at
/// the composition root; callers never import opencv_dart.
abstract interface class EdgeDetector {
  /// Returns [DetectionResult] when a 4-point convex quad is found, or [null]
  /// when no document is detected. Never throws — all failures become null.
  Future<DetectionResult?> detect(Uint8List bytes);
}
