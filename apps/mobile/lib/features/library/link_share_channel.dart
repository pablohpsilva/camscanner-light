/// Produces a shareable URL for a file by uploading it to a backend. The OCP
/// extension point for Feature 12's deferred link-share channel.
///
/// Deliberately separate from [ShareChannel] (which shares files to the OS
/// sheet and returns void): link-share returns a [Uri], which does not fit that
/// signature. No backend is wired today (link-share depends on the deferred
/// Feature 11 server), so the default [UnavailableLinkShareChannel] reports
/// [isAvailable] == false and the UI surfaces link-share as "not available yet".
abstract interface class LinkShareChannel {
  /// Whether link-sharing is currently backed by a real backend. False by default.
  bool get isAvailable;

  /// Uploads [filePath] and returns a shareable URL. Callers must gate on
  /// [isAvailable]; the default impl throws [UnsupportedError].
  Future<Uri> createLink(String filePath);
}

/// Default "no backend configured" implementation.
class UnavailableLinkShareChannel implements LinkShareChannel {
  const UnavailableLinkShareChannel();

  @override
  bool get isAvailable => false;

  @override
  Future<Uri> createLink(String filePath) =>
      throw UnsupportedError('Link sharing is not available (no backend configured).');
}
