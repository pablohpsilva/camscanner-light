import Flutter
import UIKit

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
        .registrar(forPlugin: "AttestationChannel")?.messenger {
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
