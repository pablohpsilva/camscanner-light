import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'camera_permission.dart';
import 'capture_review_screen.dart';
import 'captured_image.dart';
import 'document_scanner_service.dart';
import 'edge_detector.dart';
import 'photo_camera.dart';
import 'scan_dependencies.dart';

/// Launches the OS document scanner, applies one filter to the whole batch,
/// and saves every (already-cropped) page. Replaces the custom camera screen.
/// When [onCapture] is non-null the screen is in single-page retake mode.
class ScanScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;
  final Future<bool> Function(CapturedImage, CropCorners, ImageEnhancer)?
  onCapture;

  const ScanScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
    this.onCapture,
  });

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  late final DocumentScannerService _scanner;
  late final SaveController _saveController;
  late final PhotoCamera _camera;
  late final CameraPermission _permission;
  late final EdgeDetector _detector;
  int _pageCount = 0;
  List<CapturedImage>? _pages;
  ImageEnhancer? _enhancer;
  bool _saveFailed = false;

  @override
  void initState() {
    super.initState();
    _scanner = widget.dependencies.createDocumentScanner();
    _saveController = SaveController(repository: widget.repository);
    _camera = widget.dependencies.createPhotoCamera();
    _permission = widget.dependencies.createCameraPermission();
    _detector = widget.dependencies.createEdgeDetector();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (widget.onCapture != null) {
      await _runRetake();
      return;
    }
    final navigator = Navigator.of(context);
    final pages = await _scanner.scan(pageLimit: null);
    if (!mounted) return;
    if (pages.isEmpty) {
      navigator.pop();
      return;
    }
    final enhancer = await _pickFilter(pages.first);
    if (!mounted) return;
    if (enhancer == null) {
      navigator.pop(); // review cancelled → discard batch
      return;
    }
    setState(() {
      _pages = pages;
      _enhancer = enhancer;
    });
    await _saveAll(pages, enhancer);
    if (mounted && !_saveFailed) navigator.pop();
  }

  /// Single-shot camera + crop-enabled review, looping on Retake, then hands the
  /// reviewed page to [onCapture].
  Future<void> _runRetake() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (!await _permission.ensure()) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Camera permission is needed to retake a page.'),
        ),
      );
      navigator.pop();
      return;
    }
    while (true) {
      final photo = await _camera.capture();
      if (!mounted) return;
      if (photo == null) {
        navigator.pop();
        return;
      }
      final outcome = await _reviewRetake(photo);
      if (!mounted) return;
      if (outcome == null) {
        navigator.pop(); // system back → cancel
        return;
      }
      if (outcome is _RetakeAgain) {
        continue;
      }
      final accepted = outcome as _AcceptedPage;
      final success = await widget.onCapture!(
        photo,
        accepted.corners,
        accepted.enhancer,
      );
      if (!mounted) return;
      if (!success) {
        messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't replace page. Try again.")),
        );
      }
      navigator.pop();
      return;
    }
  }

  Future<_RetakeReview?> _reviewRetake(CapturedImage photo) {
    return Navigator.of(context).push<_RetakeReview>(
      MaterialPageRoute<_RetakeReview>(
        builder: (context) => CaptureReviewScreen(
          image: photo,
          title: 'Retake page',
          acceptLabel: 'Use',
          enableCrop: true,
          edgeDetector: _detector,
          onRetake: () => Navigator.of(context).pop(_RetakeAgain()),
          onAccept: (corners, enhancer) =>
              Navigator.of(context).pop(_AcceptedPage(corners, enhancer)),
        ),
      ),
    );
  }

  Future<void> _retry() async {
    setState(() => _saveFailed = false);
    await _saveAll(_pages!, _enhancer!);
    if (mounted && !_saveFailed) Navigator.of(context).pop();
  }

  /// Shows one filter-only review on [image]; returns the chosen enhancer, or
  /// null if the user cancelled (Retake).
  Future<ImageEnhancer?> _pickFilter(CapturedImage image) async {
    ImageEnhancer? chosen;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            enableCrop: false,
            saving: _saveController.saving,
            onRetake: () => Navigator.of(context).pop(),
            onAccept: (_, enhancer) {
              chosen = enhancer;
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
    return chosen;
  }

  Future<void> _saveAll(
    List<CapturedImage> pages,
    ImageEnhancer enhancer,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(
      pages.first,
      corners: CropCorners.fullFrame,
      enhancer: enhancer,
    );
    if (!mounted) return;
    if (doc == null) {
      setState(() => _saveFailed = true);
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    setState(() => _pageCount = 1);
    for (var i = 1; i < pages.length; i++) {
      final pos = await _saveController.addPage(
        pages[i],
        doc.id,
        corners: CropCorners.fullFrame,
        enhancer: enhancer,
      );
      if (!mounted) return;
      if (pos != null) setState(() => _pageCount = pos);
    }
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_saveFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Couldn't save the scan.",
                key: Key('scan-save-error'),
              ),
              FilledButton(
                key: const Key('scan-retry'),
                onPressed: _retry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: _pageCount == 0
            ? const Text('Scan')
            : Text('$_pageCount page${_pageCount == 1 ? '' : 's'} saved'),
      ),
      body: const Center(
        key: Key('scan-opening'),
        child: CircularProgressIndicator(),
      ),
    );
  }
}

sealed class _RetakeReview {}

class _AcceptedPage extends _RetakeReview {
  final CropCorners corners;
  final ImageEnhancer enhancer;
  _AcceptedPage(this.corners, this.enhancer);
}

class _RetakeAgain extends _RetakeReview {}
