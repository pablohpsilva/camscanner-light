import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/enhancer_mode.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'camera_permission.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'photo_camera.dart';
import 'scan_dependencies.dart';

/// Guided 2-step ID capture: shoot the front, review (Retake/Use) — accepting
/// auto-advances — then the back, then save both as a single ID-card document
/// (front = page 1, back = page 2). Exactly one photo per side; auto-cropped via
/// the edge detector with a full-frame fallback.
class IdScanScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  const IdScanScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

enum _Step { front, back, saving }

/// One accepted side: the photo plus its reviewed crop + filter.
class _SideResult {
  final CapturedImage image;
  final CropCorners corners;
  final ImageEnhancer enhancer;
  const _SideResult(this.image, this.corners, this.enhancer);
}

/// Outcome of one review screen.
sealed class _ReviewOutcome {}

class _Accepted extends _ReviewOutcome {
  final CropCorners corners;
  final ImageEnhancer enhancer;
  _Accepted(this.corners, this.enhancer);
}

class _Retake extends _ReviewOutcome {}

class _IdScanScreenState extends State<IdScanScreen> {
  late final PhotoCamera _camera;
  late final CameraPermission _permission;
  late final EdgeDetector _detector;
  late final SaveController _saveController;
  _Step _step = _Step.front;

  @override
  void initState() {
    super.initState();
    _camera = widget.dependencies.createPhotoCamera();
    _permission = widget.dependencies.createCameraPermission();
    _detector = widget.dependencies.createEdgeDetector();
    _saveController = SaveController(repository: widget.repository);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    if (!await _permission.ensure()) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Camera permission is needed to scan an ID.'),
        ),
      );
      navigator.pop();
      return;
    }

    final front = await _captureSide('Front of ID');
    if (!mounted) return;
    if (front == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.back);
    final back = await _captureSide('Back of ID');
    if (!mounted) return;
    if (back == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.saving);
    final doc = await _saveController.save(
      front.image,
      corners: front.corners,
      enhancer: front.enhancer,
    );
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save the ID. Try again.")),
      );
      navigator.pop();
      return;
    }
    final pos = await _saveController.addPage(
      back.image,
      doc.id,
      corners: back.corners,
      enhancer: back.enhancer,
    );
    if (!mounted) return;
    if (pos == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Saved the front, but the back failed. Retake it "
            "from the document.",
          ),
        ),
      );
      navigator.pop();
      return;
    }
    try {
      await widget.repository.markAsIdCard(doc.id);
    } catch (_) {
      // Non-fatal: the doc is saved; it just exports with the default layout.
    }
    if (mounted) navigator.pop();
  }

  /// Captures one side: single photo → review, looping on Retake. Returns the
  /// accepted result, or null if the user cancelled (camera-cancel or
  /// system-back on the review).
  Future<_SideResult?> _captureSide(String title) async {
    while (true) {
      final photo = await _camera.capture();
      if (!mounted || photo == null) return null;
      final outcome = await _review(photo, title);
      if (!mounted) return null;
      switch (outcome) {
        case _Accepted(:final corners, :final enhancer):
          return _SideResult(photo, corners, enhancer);
        case _Retake():
          continue;
        case null:
          return null; // system back
      }
    }
  }

  Future<_ReviewOutcome?> _review(CapturedImage photo, String title) {
    return Navigator.of(context).push<_ReviewOutcome>(
      MaterialPageRoute<_ReviewOutcome>(
        builder: (context) => CaptureReviewScreen(
          image: photo,
          title: title,
          acceptLabel: 'Use',
          enableCrop: true,
          edgeDetector: _detector,
          initialMode: EnhancerMode.none,
          onRetake: () => Navigator.of(context).pop(_Retake()),
          onAccept: (corners, enhancer) =>
              Navigator.of(context).pop(_Accepted(corners, enhancer)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_step) {
      _Step.front => 'Scan the FRONT of the ID',
      _Step.back => 'Scan the BACK of the ID',
      _Step.saving => 'Saving…',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ID')),
      body: Center(
        key: const Key('id-scan-status'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}
