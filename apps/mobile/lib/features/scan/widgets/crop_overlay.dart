import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';

class CropOverlay extends StatelessWidget {
  final Size imageSize;
  final Widget image;
  final CropCorners corners;
  final ValueChanged<CropCorners> onCornersChanged;
  final bool enabled;
  final Color highlightColor;   // NEW
  const CropOverlay({
    super.key,
    required this.imageSize,
    required this.image,
    required this.corners,
    required this.onCornersChanged,
    this.enabled = true,
    this.highlightColor = Colors.blue,   // NEW — default preserves all existing callers
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('crop-overlay'),
      builder: (context, constraints) {
        if (imageSize.width <= 0 || imageSize.height <= 0) {
          return image;
        }
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(
            box.width / imageSize.width, box.height / imageSize.height);
        final display = imageSize * scale;
        final rect =
            Offset((box.width - display.width) / 2,
                (box.height - display.height) / 2) &
            display;

        Offset posOf(Offset n) =>
            rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);

        void emitNew(String role, Offset newNorm) {
          switch (role) {
            case 'tl':
              onCornersChanged(corners.copyWith(topLeft: newNorm));
            case 'tr':
              onCornersChanged(corners.copyWith(topRight: newNorm));
            case 'br':
              onCornersChanged(corners.copyWith(bottomRight: newNorm));
            case 'bl':
              onCornersChanged(corners.copyWith(bottomLeft: newNorm));
            case 'top':
              onCornersChanged(
                  corners.copyWith(topMidDev: newNorm - corners.topCenter));
            case 'right':
              onCornersChanged(
                  corners.copyWith(rightMidDev: newNorm - corners.rightCenter));
            case 'bottom':
              onCornersChanged(corners.copyWith(
                  bottomMidDev: newNorm - corners.bottomCenter));
            case 'left':
              onCornersChanged(
                  corners.copyWith(leftMidDev: newNorm - corners.leftCenter));
          }
        }

        const r = 22.0;

        Widget buildHandle(String role, String label, Offset cornerNorm) {
          final center = posOf(cornerNorm);
          return Positioned(
            left: center.dx - r,
            top: center.dy - r,
            child: Semantics(
              label: label,
              child: _DragHandle(
                key: Key('crop-handle-$role'),
                enabled: enabled,
                cornerNorm: cornerNorm,
                rectSize: rect.size,
                highlightColor: highlightColor,   // NEW
                onNewNorm: (n) => emitNew(role, n),
              ),
            ),
          );
        }

        return Stack(
          children: [
            Positioned.fromRect(rect: rect, child: image),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _QuadPainter(
                    rect: rect,
                    corners: corners,
                    highlightColor: highlightColor,   // NEW
                  ),
                ),
              ),
            ),
            // Midpoints first so corners (added last) win overlapping hit-tests.
            buildHandle('top', 'Top edge midpoint', corners.topMid),
            buildHandle('right', 'Right edge midpoint', corners.rightMid),
            buildHandle('bottom', 'Bottom edge midpoint', corners.bottomMid),
            buildHandle('left', 'Left edge midpoint', corners.leftMid),
            buildHandle('tl', 'Top-left crop corner', corners.topLeft),
            buildHandle('tr', 'Top-right crop corner', corners.topRight),
            buildHandle('br', 'Bottom-right crop corner', corners.bottomRight),
            buildHandle('bl', 'Bottom-left crop corner', corners.bottomLeft),
          ],
        );
      },
    );
  }
}

class _DragHandle extends StatefulWidget {
  const _DragHandle({
    super.key,
    required this.enabled,
    required this.cornerNorm,
    required this.rectSize,
    required this.onNewNorm,
    required this.highlightColor,   // NEW
  });

  final bool enabled;
  final Offset cornerNorm;
  final Size rectSize;
  final void Function(Offset) onNewNorm;
  final Color highlightColor;   // NEW

  @override
  State<_DragHandle> createState() => _DragHandleState();
}

class _DragHandleState extends State<_DragHandle> {
  static const double _r = 22.0;

  Offset? _startNorm;
  Offset _accumulated = Offset.zero;

  void _onPanStart(DragStartDetails _) {
    _startNorm = widget.cornerNorm;
    _accumulated = Offset.zero;
  }

  void _onPanUpdate(DragUpdateDetails d) {
    final sn = _startNorm;
    if (sn == null) return;
    _accumulated += d.delta;
    widget.onNewNorm(Offset(
      (sn.dx + _accumulated.dx / widget.rectSize.width).clamp(0.0, 1.0),
      (sn.dy + _accumulated.dy / widget.rectSize.height).clamp(0.0, 1.0),
    ));
  }

  void _onPanEnd(DragEndDetails _) => _startNorm = null;
  void _onPanCancel() => _startNorm = null;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      // Opaque so the whole 44px target is draggable, not just the 18px dot.
      behavior: HitTestBehavior.opaque,
      onPanStart: widget.enabled ? _onPanStart : null,
      onPanUpdate: widget.enabled ? _onPanUpdate : null,
      onPanEnd: widget.enabled ? _onPanEnd : null,
      onPanCancel: widget.enabled ? _onPanCancel : null,
      child: Container(
        width: _r * 2,
        height: _r * 2,
        alignment: Alignment.center,
        child: Container(
          width: 18,
          height: 18,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: widget.highlightColor, width: 2),   // was Colors.blue
          ),
        ),
      ),
    );
  }
}

/// The closed crop boundary in display pixels, with each edge a quadratic
/// Bézier that passes through its resolved midpoint (`center + dev`). Shared by
/// the painter and unit-tested directly.
Path cropQuadPath(Rect rect, CropCorners corners) {
  Offset p(Offset n) =>
      rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);
  Offset ctrl(Offset a, Offset b, Offset devNorm) {
    final center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return p(center + devNorm * 2.0); // C = center + 2·dev
  }

  final tl = p(corners.topLeft), tr = p(corners.topRight);
  final br = p(corners.bottomRight), bl = p(corners.bottomLeft);
  final cTop = ctrl(corners.topLeft, corners.topRight, corners.topMidDev);
  final cRight = ctrl(corners.topRight, corners.bottomRight, corners.rightMidDev);
  final cBottom =
      ctrl(corners.bottomRight, corners.bottomLeft, corners.bottomMidDev);
  final cLeft = ctrl(corners.bottomLeft, corners.topLeft, corners.leftMidDev);

  return Path()
    ..moveTo(tl.dx, tl.dy)
    ..quadraticBezierTo(cTop.dx, cTop.dy, tr.dx, tr.dy)
    ..quadraticBezierTo(cRight.dx, cRight.dy, br.dx, br.dy)
    ..quadraticBezierTo(cBottom.dx, cBottom.dy, bl.dx, bl.dy)
    ..quadraticBezierTo(cLeft.dx, cLeft.dy, tl.dx, tl.dy)
    ..close();
}

class _QuadPainter extends CustomPainter {
  final Rect rect;
  final CropCorners corners;
  final Color highlightColor;   // NEW
  _QuadPainter({
    required this.rect,
    required this.corners,
    required this.highlightColor,   // NEW
  });

  @override
  void paint(Canvas canvas, Size size) {
    final quad = cropQuadPath(rect, corners);
    final outside = Path.combine(
        PathOperation.difference, Path()..addRect(Offset.zero & size), quad);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    canvas.drawPath(
        quad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = highlightColor);
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.rect != rect ||
      old.corners != corners ||
      old.highlightColor != highlightColor;   // NEW
}
