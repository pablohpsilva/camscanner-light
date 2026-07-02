/// The quality presets offered when exporting. The single source of truth for
/// the JPEG re-encode quality and downscale cap; every export path reads these.
enum ExportQuality {
  original(
      jpegQuality: null,
      maxDimension: null,
      label: 'Original',
      description: 'Full quality, largest file'),
  high(
      jpegQuality: 85,
      maxDimension: null,
      label: 'High',
      description: 'High quality'),
  medium(
      jpegQuality: 75,
      maxDimension: 2200,
      label: 'Medium',
      description: 'Good for email'),
  low(
      jpegQuality: 60,
      maxDimension: 1600,
      label: 'Low',
      description: 'Smallest file');

  const ExportQuality({
    required this.jpegQuality,
    required this.maxDimension,
    required this.label,
    required this.description,
  });

  /// JPEG quality (0–100) to re-encode at; null when [original] (no re-encode).
  final int? jpegQuality;

  /// Cap for the image's long edge in pixels; null = do not downscale.
  final int? maxDimension;

  /// Short UI label.
  final String label;

  /// One-line UI description.
  final String description;

  /// Whether this preset re-encodes the image (false only for [original]).
  bool get reencodes => jpegQuality != null;
}
