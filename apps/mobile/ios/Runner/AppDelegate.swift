import Flutter
import UIKit
import DeviceCheck
import CryptoKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Privacy: scanned documents (page images in Documents/, the OCR + full-text
    // SQLite DB in Library/Application Support/) contain PII and must not be
    // copied into the user's iCloud or encrypted iTunes/Finder backups by
    // default. iOS backs up both directories unless they carry the
    // "excluded from backup" resource flag, so we set it at every launch
    // (idempotent, best-effort — a failure here must never block startup).
    excludeUserDataFromBackup()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Register native platform channels after the plugin registry is ready.
    if let messenger = engineBridge.pluginRegistry
        .registrar(forPlugin: "AttestationChannel")?.messenger() {
      AttestationChannel.register(with: messenger)
    }
  }

  /// Marks the Documents and Application Support directories (and everything
  /// created inside them by path_provider — the image store and the SQLite DB)
  /// as excluded from iCloud/iTunes backup.
  private func excludeUserDataFromBackup() {
    let fm = FileManager.default
    let searchPaths: [FileManager.SearchPathDirectory] = [
      .documentDirectory,
      .applicationSupportDirectory,
    ]
    for searchPath in searchPaths {
      guard let dir = fm.urls(for: searchPath, in: .userDomainMask).first else { continue }
      // Application Support may not exist yet on first launch; create it so the
      // flag has something to attach to (Documents always exists).
      try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
      guard fm.fileExists(atPath: dir.path) else { continue }
      var url = dir
      var values = URLResourceValues()
      values.isExcludedFromBackup = true
      try? url.setResourceValues(values)
    }
  }
}

/// Registers the `camscanner/attestation` method channel and handles the
/// `attest` method using Apple's App Attest service (DCAppAttestService).
///
/// Kept in AppDelegate.swift (rather than a standalone file) so it is part of
/// the Runner Xcode target's compile sources without a project.pbxproj edit.
///
/// Phase-2 note: the app must have the "App Attest" capability enabled in its
/// provisioning profile and App ID (Xcode → Signing & Capabilities → + App
/// Attest) for `DCAppAttestService.shared.isSupported` to return `true` on a
/// real device. Until that entitlement is present, `isSupported` is `false` and
/// every call returns `nil`, which correctly falls back to Turnstile.
enum AttestationChannel {
  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "camscanner/attestation",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "attest" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let args = call.arguments as? [String: Any],
        let challenge = args["challenge"] as? String
      else {
        // Malformed call → treat as unsupported; fall back to Turnstile.
        result(nil)
        return
      }
      AttestationChannel.performAttest(challenge: challenge, result: result)
    }
  }

  // MARK: - Private

  private static func performAttest(challenge: String, result: @escaping FlutterResult) {
    let service = DCAppAttestService.shared
    guard service.isSupported else {
      // Simulator, or provisioning profile without the App Attest entitlement.
      result(nil)
      return
    }

    service.generateKey { keyId, error in
      guard let keyId, error == nil else {
        DispatchQueue.main.async { result(nil) }
        return
      }

      let clientDataHash = Data(SHA256.hash(data: Data(challenge.utf8)))

      service.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
        DispatchQueue.main.async {
          guard let attestation, error == nil else {
            result(nil)
            return
          }
          result([
            "token": attestation.base64EncodedString(),
            "keyId": keyId,
          ])
        }
      }
    }
  }
}
