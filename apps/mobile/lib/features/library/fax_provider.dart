/// Sends documents to a fax number via a third-party fax provider. The OCP
/// extension point for Feature 12's deferred fax channel: a real provider is a
/// new implementation; existing callers are undisturbed.
///
/// No provider is wired today (fax needs a paid off-device service), so the
/// default [UnavailableFaxProvider] reports [isAvailable] == false and the UI
/// surfaces fax as "not available yet".
abstract interface class FaxProvider {
  /// Whether faxing is currently backed by a real provider. False by default.
  bool get isAvailable;

  /// Faxes the already-scrubbed [filePaths] to [faxNumber]. Callers must gate on
  /// [isAvailable]; the default impl throws [UnsupportedError].
  Future<void> sendFax({
    required List<String> filePaths,
    required String faxNumber,
  });
}

/// Default "no provider configured" implementation.
class UnavailableFaxProvider implements FaxProvider {
  const UnavailableFaxProvider();

  @override
  bool get isAvailable => false;

  @override
  Future<void> sendFax({
    required List<String> filePaths,
    required String faxNumber,
  }) =>
      throw UnsupportedError('Fax is not available (no provider configured).');
}
