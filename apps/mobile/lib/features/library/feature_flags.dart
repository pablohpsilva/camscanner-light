/// Build-time feature flags. Each capability of the app is gated by one
/// `bool`, defaulted from `const bool.fromEnvironment('FEATURE_X', …)` so a
/// build can strip any feature with `--dart-define=FEATURE_X=false` (or a JSON
/// via `--dart-define-from-file`, the same channel the donation config uses).
///
/// Every flag defaults ON except [fax], which defaults OFF (no fax provider is
/// wired yet). A disabled flag HIDES its control entirely — see PageViewerScreen
/// / HomeScreen / EditorToolbar for the gating.
///
/// This object is INJECTABLE (threaded through LibraryDependencies.features):
/// widgets read it from their dependencies, never as a bare global const —
/// `bool.fromEnvironment` is a compile-time constant, so a global could not be
/// varied in a widget test.
class FeatureFlags {
  final bool crop;
  final bool rotate;
  final bool filter;
  final bool viewText;
  final bool retake;
  final bool share;
  final bool deletePage;
  final bool rename;
  final bool merge;
  final bool split;
  final bool deleteDocument;
  final bool exportPdf;
  final bool shareImage;
  final bool exportAllImages;
  final bool print;
  final bool protectWithPassword;
  final bool shareLink;
  final bool fax;
  final bool idCard;
  final bool scan;
  final bool import;

  const FeatureFlags({
    this.crop = const bool.fromEnvironment('FEATURE_CROP', defaultValue: true),
    this.rotate =
        const bool.fromEnvironment('FEATURE_ROTATE', defaultValue: true),
    this.filter =
        const bool.fromEnvironment('FEATURE_FILTER', defaultValue: true),
    this.viewText =
        const bool.fromEnvironment('FEATURE_VIEW_TEXT', defaultValue: true),
    this.retake =
        const bool.fromEnvironment('FEATURE_RETAKE', defaultValue: true),
    this.share =
        const bool.fromEnvironment('FEATURE_SHARE', defaultValue: true),
    this.deletePage =
        const bool.fromEnvironment('FEATURE_DELETE_PAGE', defaultValue: true),
    this.rename =
        const bool.fromEnvironment('FEATURE_RENAME', defaultValue: true),
    this.merge =
        const bool.fromEnvironment('FEATURE_MERGE', defaultValue: true),
    this.split =
        const bool.fromEnvironment('FEATURE_SPLIT', defaultValue: true),
    this.deleteDocument = const bool.fromEnvironment(
      'FEATURE_DELETE_DOCUMENT',
      defaultValue: true,
    ),
    this.exportPdf =
        const bool.fromEnvironment('FEATURE_EXPORT_PDF', defaultValue: true),
    this.shareImage =
        const bool.fromEnvironment('FEATURE_SHARE_IMAGE', defaultValue: true),
    this.exportAllImages = const bool.fromEnvironment(
      'FEATURE_EXPORT_ALL_IMAGES',
      defaultValue: true,
    ),
    this.print =
        const bool.fromEnvironment('FEATURE_PRINT', defaultValue: true),
    this.protectWithPassword = const bool.fromEnvironment(
      'FEATURE_PROTECT_WITH_PASSWORD',
      defaultValue: true,
    ),
    this.shareLink =
        const bool.fromEnvironment('FEATURE_SHARE_LINK', defaultValue: true),
    this.fax =
        const bool.fromEnvironment('FEATURE_FAX', defaultValue: false),
    this.idCard =
        const bool.fromEnvironment('FEATURE_ID_CARD', defaultValue: true),
    this.scan =
        const bool.fromEnvironment('FEATURE_SCAN', defaultValue: true),
    this.import =
        const bool.fromEnvironment('FEATURE_IMPORT', defaultValue: true),
  });
}
