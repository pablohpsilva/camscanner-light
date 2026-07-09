import Flutter
import UIKit
import DeviceCheck
import CryptoKit

/// Registers the `camscanner/attestation` method channel and handles the
/// `attest` method using Apple's App Attest service (DCAppAttestService).
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
