import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/ream_colors.dart';
import '../../theme/ream_theme.dart';
import '../../theme/widgets/ream_back_header.dart';
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
          Size(info.image.width.toDouble(), info.image.height.toDouble()),
        );
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
  final int quarterTurns;
  final Future<Size> Function(String) decodeImageSize;

  const EditCropScreen({
    super.key,
    required this.imagePath,
    required this.initialCorners,
    this.quarterTurns = 0,
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
    widget
        .decodeImageSize(widget.imagePath)
        .then((size) {
          if (!mounted) return;
          final oddTurn = widget.quarterTurns.isOdd;
          setState(
            () => _imageSize = oddTurn ? Size(size.height, size.width) : size,
          );
        })
        .catchError((_) {
          /* leave _imageSize null — overlay skipped, image still shown */
        });
  }

  Widget _imageWidget(ReamColors r) => RotatedBox(
    quarterTurns: widget.quarterTurns,
    child: Image.file(
      File(widget.imagePath),
      key: const Key('edit-crop-image'),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Center(
        child: Icon(Icons.broken_image_outlined, color: r.muted, size: 64),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Theme(
        data: ReamTheme.dark(),
        child: Builder(
          builder: (context) {
            final r = context.ream;
            return Scaffold(
              appBar: ReamBackHeader(
                title: 'Review & clean',
                backKey: const Key('edit-crop-back'),
                onBack: () => Navigator.of(context).pop(),
                trailing: IconButton(
                  key: const Key('edit-crop-accept'),
                  onPressed: () => Navigator.of(context).pop(_corners),
                  icon: Icon(Icons.check, color: r.green),
                  tooltip: 'Save',
                ),
              ),
              body: ColoredBox(
                color: r.paper,
                child: SizedBox.expand(
                  child: size == null
                      ? Center(child: _imageWidget(r))
                      : CropOverlay(
                          imageSize: size,
                          image: _imageWidget(r),
                          corners: _corners,
                          onCornersChanged: (c) => setState(() => _corners = c),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
