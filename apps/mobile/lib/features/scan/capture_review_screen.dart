import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../library/crop_corners.dart';
import '../library/enhancer_for_mode.dart';
import '../library/enhancer_mode.dart';
import '../library/image_enhancer.dart';
import '../library/image_size_resolver.dart';
import '../library/preview_proxy.dart';
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

  /// B2 live-preview seams. [previewDebounce] coalesces rapid filter switches;
  /// [proxyRunner] downsizes the source to a preview proxy (defaults to
  /// `compute(previewProxyJpeg, …)`); [previewEnhancerFor] maps a mode to the enhancer
  /// used for the ON-SCREEN preview (defaults to [enhancerForMode]). Accept is
  /// unaffected — it still enhances the FULL-res capture via [enhancerForMode].
  final Duration previewDebounce;
  final Future<Uint8List> Function(Uint8List bytes)? proxyRunner;
  final ImageEnhancer Function(EnhancerMode mode)? previewEnhancerFor;

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
    this.previewDebounce = const Duration(milliseconds: 250),
    this.proxyRunner,
    this.previewEnhancerFor,
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

  // B2 live preview: the enhanced proxy shown on the big image, or null to show
  // the raw capture (Original / not-yet-computed). A generation counter
  // discards stale async results, and a debounce timer coalesces rapid switches.
  Uint8List? _previewBytes;
  bool _previewComputing = false;
  Timer? _previewDebounce;
  int _previewGen = 0;

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

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  // B2: user picked a filter. Update the selected mode (drives Accept + the
  // strip's pill) and (re)schedule a debounced live preview on the big image.
  void _onModeChanged(EnhancerMode mode) {
    setState(() => _mode = mode);
    _schedulePreview(mode);
  }

  void _schedulePreview(EnhancerMode mode) {
    _previewDebounce?.cancel();
    final gen = ++_previewGen; // invalidate any in-flight compute
    if (mode == EnhancerMode.none) {
      // Original: no enhancement — show the raw capture, drop any spinner.
      setState(() {
        _previewBytes = null;
        _previewComputing = false;
      });
      return;
    }
    setState(() => _previewComputing = true);
    _previewDebounce = Timer(
      widget.previewDebounce,
      () => _computePreview(mode, gen),
    );
  }

  Future<void> _computePreview(EnhancerMode mode, int gen) async {
    final bytes = _sourceBytes;
    if (bytes == null) {
      if (mounted && gen == _previewGen) {
        setState(() => _previewComputing = false);
      }
      return;
    }
    try {
      final proxyRun =
          widget.proxyRunner ?? ((b) => compute(previewProxyJpeg, b));
      final proxy = await proxyRun(bytes);
      if (!mounted || gen != _previewGen) return;
      final enhancerFor = widget.previewEnhancerFor ?? enhancerForMode;
      final out = await enhancerFor(mode).enhance(proxy);
      if (!mounted || gen != _previewGen) return;
      setState(() {
        _previewBytes = out;
        _previewComputing = false;
      });
    } catch (_) {
      // Preview failed — fall back to the raw capture (never a stuck spinner).
      if (mounted && gen == _previewGen) {
        setState(() {
          _previewBytes = null;
          _previewComputing = false;
        });
      }
    }
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

  Widget _imageWidget() {
    const errorIcon = Icon(
      Icons.broken_image_outlined,
      key: Key('review-image-error'),
      color: Colors.white54,
      size: 64,
    );
    // B2: show the enhanced live preview when available, else the raw capture.
    // Both keep the `review-image` key so callers/tests are unaffected.
    final preview = _previewBytes;
    if (preview != null) {
      return Image.memory(
        preview,
        key: const Key('review-image'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stack) => errorIcon,
      );
    }
    return Image.file(
      File(widget.image.path),
      key: const Key('review-image'),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) => errorIcon,
    );
  }

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
                // B2: small spinner while the live preview is being computed.
                if (_previewComputing && !widget.saving)
                  const Positioned(
                    top: 12,
                    right: 12,
                    child: SizedBox(
                      key: Key('review-preview-loading'),
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
              ],
            ),
          ),
          // B2: wrap the strip in the App theme scope so it renders in the
          // design system (matches EditFilterScreen).
          Theme(
            data: AppTheme.dark(),
            child: FilterPickerStrip(
              key: const Key('filter-picker-strip'),
              selectedMode: _mode,
              onModeChanged: _onModeChanged,
              sourceBytes: _sourceBytes,
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
