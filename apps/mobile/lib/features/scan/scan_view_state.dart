/// The states of the camera (Scan) screen. The screen renders exactly one
/// view per status; [ScanController] drives the transitions.
enum ScanStatus {
  /// Permission/camera are being resolved (transient, on entry).
  checking,

  /// Permission granted and the camera initialized — show the live preview.
  ready,

  /// Permission was denied — show the rationale and an Open Settings action.
  permissionDenied,

  /// No camera, or the camera failed to initialize — show a graceful message.
  unavailable,
}
