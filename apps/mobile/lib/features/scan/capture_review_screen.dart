import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/auto_enhancer.dart';
import '../library/bw_enhancer.dart';
import '../library/color_enhancer.dart';
import '../library/grayscale_enhancer.dart';
import '../library/image_enhancer.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'widgets/crop_overlay.dart';

Future<Size> _resolveImageSize(String path) {
  final completer = Completer<Size>();
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    if (!completer.isCompleted) {
      completer.complete(Size(
          info.image.width.toDouble(), info.image.height.toDouble()));
    }
    stream.removeListener(listener);
  }, onError: (e, st) {
    if (!completer.isCompleted) completer.completeError(e);
    stream.removeListener(listener);
  });
  stream.addListener(listener);
  return completer.future;
}

Future<Uint8List> _defaultReadBytes(String path) => File(path).readAsBytes();

enum _EnhancerMode { none, grayscale, bw, auto, color }

class CaptureReviewScreen extends StatefulWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final void Function(CropCorners corners, ImageEnhancer enhancer) onAccept;
  final bool saving;
  final Future<Size> Function(String path) decodeImageSize;
  final Future<Uint8List> Function(String path) readBytes;   // NEW
  final EdgeDetector? edgeDetector;                          // NEW

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
    this.saving = false,
    this.decodeImageSize = _resolveImageSize,
    this.readBytes = _defaultReadBytes,     // NEW
    this.edgeDetector,                      // NEW
  });

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  CropCorners _corners = CropCorners.fullFrame;
  Size? _imageSize;
  double? _detectionConfidence;   // NEW: null = pending/failed; ≥0 = result received
  bool _userInteracted = false;   // NEW: true once user touches a handle or taps Reset
  _EnhancerMode _mode = _EnhancerMode.none;

  Color get _highlightColor =>
      (_detectionConfidence ?? -1) >= 0.5 ? Colors.green : Colors.blue;

  @override
  void initState() {
    super.initState();
    widget.decodeImageSize(widget.image.path).then((size) {
      if (!mounted) return;
      setState(() => _imageSize = size);
    }).catchError((_) {});
    _runDetection();   // NEW — concurrent with decodeImageSize
  }

  Future<void> _runDetection() async {
    final detector = widget.edgeDetector;
    if (detector == null) return;
    try {
      final bytes = await widget.readBytes(widget.image.path);
      final result = await detector.detect(bytes);
      if (!mounted || _userInteracted) return;
      if (result != null) {
        setState(() {
          _corners = result.corners;
          _detectionConfidence = result.confidence;
        });
      }
    } catch (_) {
      // Silent fallback — leave _corners as fullFrame, _detectionConfidence null.
    }
  }

  Widget _imageWidget() => Image.file(
        File(widget.image.path),
        key: const Key('review-image'),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => const Icon(
          Icons.broken_image_outlined,
          key: Key('review-image-error'),
          color: Colors.white54,
          size: 64,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final canCrop = size != null && !widget.saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          IconButton(
            key: const Key('grayscale-toggle'),
            icon: Icon(_mode == _EnhancerMode.grayscale
                ? Icons.filter_b_and_w
                : Icons.filter_b_and_w_outlined),
            tooltip: _mode == _EnhancerMode.grayscale ? 'Grayscale on' : 'Grayscale off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.grayscale
                    ? _EnhancerMode.none
                    : _EnhancerMode.grayscale),
          ),
          IconButton(
            key: const Key('bw-toggle'),
            icon: Icon(
              Icons.contrast,
              color: _mode == _EnhancerMode.bw
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _mode == _EnhancerMode.bw ? 'B&W on' : 'B&W off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.bw
                    ? _EnhancerMode.none
                    : _EnhancerMode.bw),
          ),
          IconButton(
            key: const Key('auto-toggle'),
            icon: Icon(
              Icons.auto_fix_high,
              color: _mode == _EnhancerMode.auto
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _mode == _EnhancerMode.auto ? 'Auto on' : 'Auto off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.auto
                    ? _EnhancerMode.none
                    : _EnhancerMode.auto),
          ),
          IconButton(
            key: const Key('color-toggle'),
            icon: Icon(
              Icons.color_lens,
              color: _mode == _EnhancerMode.color
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: _mode == _EnhancerMode.color ? 'Color on' : 'Color off',
            onPressed: () => setState(() => _mode =
                _mode == _EnhancerMode.color
                    ? _EnhancerMode.none
                    : _EnhancerMode.color),
          ),
        ],
      ),
      body: Stack(
        children: [
          ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: size == null
                  ? Center(child: _imageWidget())
                  : CropOverlay(
                      imageSize: size,
                      image: _imageWidget(),
                      corners: _corners,
                      enabled: !widget.saving,
                      highlightColor: _highlightColor,   // NEW
                      onCornersChanged: (c) => setState(() {
                        _userInteracted = true;   // NEW
                        _corners = c;
                      }),
                    ),
            ),
          ),
          if (widget.saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                    child: CircularProgressIndicator(key: Key('review-saving'))),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                key: const Key('review-retake'),
                onPressed: widget.saving ? null : widget.onRetake,
                icon: const Icon(Icons.replay),
                label: const Text('Retake'),
              ),
              TextButton(
                key: const Key('crop-reset'),
                onPressed: canCrop
                    ? () => setState(() {
                          _userInteracted = true;           // NEW — block in-flight detection
                          _corners = CropCorners.fullFrame;
                        })
                    : null,
                child: const Text('Reset'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: widget.saving
                    ? null
                    : () => widget.onAccept(
                          _corners,
                          switch (_mode) {
                            _EnhancerMode.grayscale => const GrayscaleEnhancer(),
                            _EnhancerMode.bw        => const BwEnhancer(),
                            _EnhancerMode.auto      => const AutoEnhancer(),
                            _EnhancerMode.color     => const ColorEnhancer(),
                            _EnhancerMode.none      => const NoneEnhancer(),
                          },
                        ),
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
