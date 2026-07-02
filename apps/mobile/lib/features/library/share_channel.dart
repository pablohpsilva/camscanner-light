import 'package:share_plus/share_plus.dart';

/// Shares files to the OS share sheet (Mail, Messages, WhatsApp, etc.).
/// Injectable (DIP) so tests and the on-device BDD use a recording fake instead
/// of the native share sheet (which cannot be driven by an automated test).
///
/// This is the OCP extension point for Feature 12: a future on-device link-share
/// channel is just another implementation — existing callers are undisturbed.
/// Path-based on purpose, so `share_plus`'s `XFile`/`ShareParams` types stay
/// entirely inside [SystemShareChannel] and never leak into the abstraction.
abstract interface class ShareChannel {
  /// Shares [filePaths] via the OS share sheet, with an optional [subject]
  /// (used by targets like Mail). Files must already be metadata-scrubbed by
  /// their producer — this channel does not scrub (DRY).
  Future<void> share(List<String> filePaths, {String? subject});
}

/// Production channel backed by the `share_plus` package. The only file in the
/// app that imports `share_plus`.
class SystemShareChannel implements ShareChannel {
  const SystemShareChannel();

  @override
  Future<void> share(List<String> filePaths, {String? subject}) async {
    await SharePlus.instance.share(
      ShareParams(
        files: filePaths.map((p) => XFile(p)).toList(),
        subject: subject,
      ),
    );
  }
}
