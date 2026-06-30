import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/save_controller.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'scan_controller.dart';
import 'scan_dependencies.dart';
import 'scan_view_state.dart';
import 'widgets/camera_preview_view.dart';
import 'widgets/camera_unavailable_view.dart';
import 'widgets/permission_denied_view.dart';

/// The Scan screen: requests camera permission and shows the live preview, or
/// a graceful fallback. Capture (shutter) → review screen lives here (A3/B1).
class CameraScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  const CameraScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  late final ScanController _controller;
  late final SaveController _saveController;
  late final EdgeDetector _edgeDetector;

  @override
  void initState() {
    super.initState();
    _controller = ScanController(
      permission: widget.dependencies.createPermissionService(),
      preview: widget.dependencies.createPreviewController(),
    );
    _controller.start();
    _saveController = SaveController(repository: widget.repository);
    _edgeDetector = widget.dependencies.createEdgeDetector();
  }

  @override
  void dispose() {
    // _edgeDetector is not disposed — OpenCvEdgeDetector is a const stateless instance.
    _controller.dispose();
    _saveController.dispose();
    super.dispose();
  }

  Future<void> _onShutter() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final image = await _controller.capture();
    if (!mounted) return;
    if (image == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Try again.')),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            edgeDetector: _edgeDetector,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: (corners) => _onAccept(image, corners),
          ),
        ),
      ),
    );
  }

  Future<void> _onAccept(CapturedImage image, CropCorners corners) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(image, corners: corners);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan')),
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
