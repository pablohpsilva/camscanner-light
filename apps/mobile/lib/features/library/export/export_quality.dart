import '../../../l10n/l10n.dart';

/// The quality presets offered when exporting. The single source of truth for
/// the JPEG re-encode quality and downscale cap; every export path reads these.
enum ExportQuality {
  original(jpegQuality: null, maxDimension: null),
  high(jpegQuality: 85, maxDimension: null),
  medium(jpegQuality: 75, maxDimension: 2200),
  low(jpegQuality: 60, maxDimension: 1600);

  const ExportQuality({required this.jpegQuality, required this.maxDimension});

  /// JPEG quality (0–100) to re-encode at; null when [original] (no re-encode).
  final int? jpegQuality;

  /// Cap for the image's long edge in pixels; null = do not downscale.
  final int? maxDimension;

  /// Whether this preset re-encodes the image (false only for [original]).
  bool get reencodes => jpegQuality != null;
}

/// Localized label/description for each [ExportQuality] preset. Resolution
/// happens in `build` (via `context.l10n`) since enum consts can't hold a
/// `BuildContext`-dependent value.
extension ExportQualityL10n on ExportQuality {
  String label(AppLocalizations l10n) => switch (this) {
    ExportQuality.original => l10n.exportQualityOriginal,
    ExportQuality.high => l10n.exportQualityHigh,
    ExportQuality.medium => l10n.exportQualityMedium,
    ExportQuality.low => l10n.exportQualityLow,
  };

  String description(AppLocalizations l10n) => switch (this) {
    ExportQuality.original => l10n.exportQualityOriginalDesc,
    ExportQuality.high => l10n.exportQualityHighDesc,
    ExportQuality.medium => l10n.exportQualityMediumDesc,
    ExportQuality.low => l10n.exportQualityLowDesc,
  };
}
