import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../library/crop_corners.dart';
import '../library/enhancer_for_mode.dart';
import '../library/enhancer_mode.dart';
import '../library/image_enhancer.dart';
import '../library/image_size_resolver.dart';
import 'captured_image.dart';
import 'edge_detector.dart';
import 'widgets/crop_overlay.dart';
import 'widgets/filter_picker_strip.dart';

Future<Uint8List> _defaultReadBytes(String path) => File(path).readAsBytes();

class CaptureReviewScreen extends StatefulWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final void Function(CropCorners corners, ImageEnhancer enhancer) onAccept;
  final bool saving;
  final bool
  enableCrop; // NEW: false = filter-only (already-cropped scanner page)
  final Future<Size> Function(String path) decodeImageSize;
  final Future<Uint8List> Function(String path) readBytes; // NEW
  final EdgeDetector? edgeDetector; // NEW

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
    this.saving = false,
    this.enableCrop = true,
    this.decodeImageSize = resolveImageSize,
    this.readBytes = _defaultReadBytes, // NEW
    this.edgeDetector, // NEW
  });

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  CropCorners _corners = CropCorners.fullFrame;
  Size? _imageSize;
  double?
  _detectionConfidence; // NEW: null = pending/failed; ≥0 = result received
  bool _userInteracted =
      false; // NEW: true once user touches a handle or taps Reset
  EnhancerMode _mode = EnhancerMode.auto;
  Uint8List? _sourceBytes;
  // The source JPEG is read off disk ONCE (P13 PERF-1): both the _sourceBytes
  // setter and _runDetection await this single future instead of re-reading.
  late final Future<Uint8List> _bytesFuture;

  // Three tiers: confident (green), best-guess-please-check (amber), and
  // fallback/full-frame (blue). Low-confidence detections still snap the dots
  // to a best guess, so amber tells the user to verify rather than trust.
  Color get _highlightColor {
    final c = _detectionConfidence ?? -1;
    if (c >= 0.6) return Colors.green;
    if (c >= 0.3) return Colors.amber;
    return Colors.blue;
  }

  @override
  void initState() {
    super.initState();
    _bytesFuture = widget.readBytes(widget.image.path); // single read (PERF-1)
    widget
        .decodeImageSize(widget.image.path)
        .then((size) {
          if (!mounted) return;
          setState(() => _imageSize = size);
        })
        .catchError((_) {});
    _runDetection(); // NEW — concurrent with decodeImageSize
    _bytesFuture
        .then((b) {
          if (!mounted) return;
          setState(() => _sourceBytes = b);
        })
        .catchError((_) {});
  }

  Future<void> _runDetection() async {
    if (!widget.enableCrop) return;
    final detector = widget.edgeDetector;
    if (detector == null) return;
    try {
      final bytes = await _bytesFuture; // reuse the single read (PERF-1)
      // Skip the ~5 s detection isolate entirely if the user already dragged a
      // handle or hit Reset while the bytes were loading (P13 PERF-2).
      if (!mounted || _userInteracted) return;
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
    final l10n = context.l10n;
    final size = _imageSize;
    final canCrop = size != null && !widget.saving;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.captureReviewTitle)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                ColoredBox(
                  color: Colors.black,
                  child: SizedBox.expand(
                    child: (!widget.enableCrop || size == null)
                        ? Center(child: _imageWidget())
                        : CropOverlay(
                            imageSize: size,
                            image: _imageWidget(),
                            corners: _corners,
                            enabled: !widget.saving,
                            highlightColor: _highlightColor,
                            onCornersChanged: (c) => setState(() {
                              _userInteracted = true;
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
                        child: CircularProgressIndicator(
                          key: Key('review-saving'),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          FilterPickerStrip(
            key: const Key('filter-picker-strip'),
            selectedMode: _mode,
            onModeChanged: (m) => setState(() => _mode = m),
            sourceBytes: _sourceBytes,
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
                label: Text(l10n.commonRetake),
              ),
              if (widget.enableCrop)
                TextButton(
                  key: const Key('crop-reset'),
                  onPressed: canCrop
                      ? () => setState(() {
                          _userInteracted =
                              true; // NEW — block in-flight detection
                          _corners = CropCorners.fullFrame;
                        })
                      : null,
                  child: Text(l10n.captureReviewReset),
                ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: widget.saving
                    ? null
                    : () => widget.onAccept(_corners, enhancerForMode(_mode)),
                icon: const Icon(Icons.check),
                label: Text(l10n.captureReviewAccept),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
