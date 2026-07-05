import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'camera_frame.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'gallery_picker.dart';
import 'scan_controller.dart';
import 'scan_dependencies.dart';
import 'scan_flash_mode.dart';
import 'scan_view_state.dart';
import 'widgets/camera_preview_view.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/permission_denied_view.dart';

/// The Scan screen: requests camera permission and shows the live preview, or
/// a graceful fallback. Capture (shutter) → review screen lives here (A3/B1).
/// F3: stream-based detection loop draws a live quad outline on the preview.
class CameraScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  /// When non-null, the screen is in single-capture (retake) mode: after the
  /// user accepts a capture in review, [onCapture] is invoked with the image,
  /// crop corners, and enhancer. If it returns true the camera screen pops back
  /// to its caller (one page only — no accumulation, no "Done"). When null
  /// (default) the screen keeps its create/append behavior.
  final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)? onCapture;

  const CameraScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
    this.onCapture,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final ScanController _controller;
  late final SaveController _saveController;
  late final EdgeDetector _edgeDetector;
  late final GalleryPicker _galleryPicker;
  bool _sampling = false;
  bool _isDetecting = false;
  ScanFlashMode _flashMode = ScanFlashMode.off;
  DetectionResult? _liveResult;
  int? _activeDocId;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScanController(
      permission: widget.dependencies.createPermissionService(),
      preview: widget.dependencies.createPreviewController(),
    );
    // Register before start() so we catch the checking→ready transition.
    _controller.addListener(_onControllerChanged);
    _controller.start();
    _saveController = SaveController(repository: widget.repository);
    _edgeDetector = widget.dependencies.createEdgeDetector();
    _galleryPicker = widget.dependencies.createGalleryPicker();
  }

  /// Fired on every [ScanController] notification. Starts sampling the moment
  /// the camera becomes ready (and not capturing). The `_sampling` guard in
  /// [_startSampling] makes redundant calls safe.
  void _onControllerChanged() {
    if (_controller.status == ScanStatus.ready &&
        !_sampling &&
        !_controller.capturing) {
      _startSampling();
    }
  }

  void _startSampling() {
    if (_sampling) return;
    _sampling = true;
    _controller.preview.startSampling(_onFrame);
  }

  void _stopSampling() {
    if (!_sampling) return;
    _sampling = false;
    _controller.preview.stopSampling();
  }

  Future<void> _onFrame(CameraFrame frame) async {
    if (_isDetecting ||
        _controller.capturing ||
        _controller.status != ScanStatus.ready) {
      return;
    }
    _isDetecting = true;
    try {
      final sw = kDebugMode ? (Stopwatch()..start()) : null;
      final result = await _edgeDetector.detectFrame(frame);
      if (sw != null) {
        debugPrint('[scan] detectFrame ${sw.elapsedMilliseconds}ms');
      }
      if (!mounted) return;
      setState(() {
        _liveResult =
            (result != null && result.confidence >= 0.5) ? result : null;
      });
    } finally {
      _isDetecting = false;
    }
  }

  void _onFlashModeChanged(ScanFlashMode mode) {
    setState(() => _flashMode = mode);
    _controller.preview.setFlashMode(mode);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _stopSampling();
    // _edgeDetector is not disposed — OpenCvEdgeDetector is a const stateless instance.
    _controller.dispose();
    _saveController.dispose();
    super.dispose();
  }

  Future<void> _reviewAndSave(CapturedImage image) async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            edgeDetector: _edgeDetector,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: (corners, enhancer) => _onAccept(image, corners, enhancer),
          ),
        ),
      ),
    );
  }

  Future<void> _onShutter() async {
    _stopSampling();
    final messenger = ScaffoldMessenger.of(context);
    final image = await _controller.capture();
    // Re-stop: the controller's post-capture notifyListeners() fires
    // _onControllerChanged which may restart sampling before we resume.
    _stopSampling();
    if (!mounted) return;
    if (image == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Try again.')),
      );
      if (mounted && _controller.status == ScanStatus.ready) {
        _startSampling();
      }
      return;
    }
    await _reviewAndSave(image);
    if (mounted && _controller.status == ScanStatus.ready) {
      _startSampling();
    }
  }

  Future<void> _onImport() async {
    _stopSampling();
    final messenger = ScaffoldMessenger.of(context);
    CapturedImage? image;
    try {
      image = await _galleryPicker.pick();
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't import photo")),
      );
      if (_controller.status == ScanStatus.ready) _startSampling();
      return;
    }
    if (!mounted) return;
    if (image == null) {
      if (_controller.status == ScanStatus.ready) _startSampling();
      return;
    }
    await _reviewAndSave(image);
    if (mounted && _controller.status == ScanStatus.ready) _startSampling();
  }

  Future<void> _onAccept(
      CapturedImage image, CropCorners corners, ImageEnhancer enhancer) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (widget.onCapture != null) {
      final ok = await widget.onCapture!(image, corners, enhancer);
      if (!mounted) return;
      if (!ok) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't replace page. Try again.")),
        );
        navigator.pop(); // dismiss review, stay in camera to retry
        return;
      }
      navigator.pop(); // dismiss review
      navigator.pop(); // leave camera, back to viewer
      return;
    }

    if (_activeDocId == null) {
      // First page: create new document.
      final doc = await _saveController.save(image,
          corners: corners, enhancer: enhancer);
      if (!mounted) return;
      if (doc == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save document. Try again.")),
        );
        return;
      }
      setState(() {
        _activeDocId = doc.id;
        _pageCount = 1;
      });
      navigator.pop(); // dismiss review, stay in camera
    } else {
      // Subsequent pages: append to active document.
      final position = await _saveController.addPage(image, _activeDocId!,
          corners: corners, enhancer: enhancer);
      if (!mounted) return;
      if (position == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't save page. Try again.")),
        );
        navigator.pop(); // return to camera; _activeDocId stays set
        return;
      }
      setState(() => _pageCount = position);
      navigator.pop();
    }
  }

  void _onDone() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _pageCount == 0
            ? const Text('Scan')
            : Text('$_pageCount page${_pageCount == 1 ? '' : 's'} saved'),
        actions: [
          IconButton(
            key: const Key('camera-import'),
            icon: const Icon(Icons.photo_library_outlined),
            tooltip: 'Import from gallery',
            onPressed: _onImport,
          ),
          if (_pageCount > 0)
            IconButton(
              key: const Key('camera-done'),
              icon: const Icon(Icons.check),
              tooltip: 'Done scanning',
              onPressed: _onDone,
            ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          switch (_controller.status) {
            case ScanStatus.checking:
              return const Center(
                key: Key('scan-checking'),
                child: CircularProgressIndicator(),
              );
            case ScanStatus.ready:
              return CameraPreviewView(
                key: const Key('scan-preview'),
                controller: _controller.preview,
                capturing: _controller.capturing,
                onShutter: _onShutter,
                liveCorners: _liveResult?.corners,
                previewSize: _liveResult != null
                    ? _controller.preview.previewSize
                    : null,
                flashMode: _flashMode,
                onFlashModeChanged: _onFlashModeChanged,
              );
            case ScanStatus.permissionDenied:
              return PermissionDeniedView(
                permanentlyDenied: _controller.permanentlyDenied,
                onOpenSettings: _controller.openSettings,
              );
            case ScanStatus.unavailable:
              return const CameraUnavailableView();
          }
        },
      ),
    );
  }
}
