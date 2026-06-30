import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../scan/widgets/crop_overlay.dart';
import 'crop_corners.dart';

/// Resolves the EXIF-applied natural size of the image at [path].
/// Uses the same approach as CaptureReviewScreen — the framework decoder bakes
/// the Orientation tag so this size matches the displayed image.
Future<Size> _resolveImageSize(String path) {
  final completer = Completer<Size>();
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener(
    (info, _) {
      if (!completer.isCompleted) {
        completer.complete(
            Size(info.image.width.toDouble(), info.image.height.toDouble()));
      }
      stream.removeListener(listener);
    },
    onError: (e, st) {
      if (!completer.isCompleted) completer.completeError(e);
      stream.removeListener(listener);
    },
  );
  stream.addListener(listener);
  return completer.future;
}

/// Full-screen crop editor. Shows the original JPEG (at [imagePath]) with a
/// draggable [CropOverlay] seeded from [initialCorners]. Accept pops with the
/// chosen [CropCorners]; Cancel (back button) pops with null.
///
/// [decodeImageSize] is injectable for tests — defaults to [_resolveImageSize].
/// Until the size resolves, the image is shown without handles (same pattern as
/// CaptureReviewScreen). If size resolution fails, the screen stays overlay-free.
class EditCropScreen extends StatefulWidget {
  final String imagePath;
  final CropCorners initialCorners;
  final Future<Size> Function(String) decodeImageSize;

  const EditCropScreen({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    this.decodeImageSize = _resolveImageSize,
  });

  @override
  State<EditCropScreen> createState() => _EditCropScreenState();
}

class _EditCropScreenState extends State<EditCropScreen> {
  late CropCorners _corners;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    _corners = widget.initialCorners;
    widget.decodeImageSize(widget.imagePath).then((size) {
      if (!mounted) return;
      setState(() => _imageSize = size);
    }).catchError((_) {/* leave _imageSize null — overlay skipped, image still shown */});
  }

  Widget _imageWidget() => Image.file(
        File(widget.imagePath),
        key: const Key('edit-crop-image'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined,
              color: Colors.white54, size: 64),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit crop'),
        actions: [
          TextButton(
            key: const Key('edit-crop-accept'),
            onPressed: () => Navigator.of(context).pop(_corners),
            child: const Text('Accept'),
          ),
        ],
      ),
      body: ColoredBox(
        color: Colors.black,
        child: SizedBox.expand(
          child: size == null
              ? Center(child: _imageWidget())
              : CropOverlay(
                  imageSize: size,
                  image: _imageWidget(),
                  corners: _corners,
                  onCornersChanged: (c) => setState(() => _corners = c),
                ),
        ),
      ),
    );
  }
}
