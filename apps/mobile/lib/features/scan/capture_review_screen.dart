import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import 'captured_image.dart';
import 'widgets/crop_overlay.dart';

/// Default EXIF-applied natural-size resolver: the framework decoder bakes the
/// Orientation tag, so this size matches the displayed (and stored) image.
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

/// Shows a freshly captured [image] with Retake / Reset / Accept. Once the
/// image's natural size resolves, draws a draggable crop overlay; Accept hands
/// the chosen [CropCorners] up (the parent saves). Saving disables actions.
class CaptureReviewScreen extends StatefulWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final ValueChanged<CropCorners> onAccept;
  final bool saving;
  final Future<Size> Function(String path) decodeImageSize;

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
    this.saving = false,
    this.decodeImageSize = _resolveImageSize,
  });

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  CropCorners _corners = CropCorners.fullFrame;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    widget.decodeImageSize(widget.image.path).then((size) {
      if (!mounted) return;
      setState(() => _imageSize = size);
    }).catchError((_) {/* leave _imageSize null -> plain image */});
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
      appBar: AppBar(title: const Text('Review')),
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
                      onCornersChanged: (c) => setState(() => _corners = c),
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
                    ? () => setState(() => _corners = CropCorners.fullFrame)
                    : null,
                child: const Text('Reset'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: widget.saving ? null : () => widget.onAccept(_corners),
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
