import 'dart:typed_data';

/// Strips identifying metadata from an image's bytes before it is persisted.
/// B1 ships a JPEG implementation; Feature 07 swaps in the shared scrubber.
abstract interface class ImageMetadataScrubber {
  /// Returns scrubbed bytes. Throws [MetadataScrubException] if the input is
  /// not a format this scrubber can safely process (fail closed — never write
  /// unverified data).
  Uint8List scrub(Uint8List bytes);
}

class MetadataScrubException implements Exception {
  final String message;
  const MetadataScrubException(this.message);
  @override
  String toString() => 'MetadataScrubException: $message';
}
