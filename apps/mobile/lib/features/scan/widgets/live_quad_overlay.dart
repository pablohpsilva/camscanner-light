import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';

/// Draws a quad outline (green when confident) over the live camera preview.
/// Non-interactive — callers wrap in [IgnorePointer]. Fitted-rect math
/// matches [CropOverlay] so normalized corners align correctly.
class LiveQuadOverlay extends StatelessWidget {
  final CropCorners corners;
  final Size previewSize;
  final Color color;

  const LiveQuadOverlay({
    super.key,
    required this.corners,
    required this.previewSize,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('live-quad-overlay'),
      builder: (context, constraints) {
        if (previewSize.width <= 0 || previewSize.height <= 0) {
          return const SizedBox.expand();
        }
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(
          box.width / previewSize.width,
          box.height / previewSize.height,
        );
        final display = previewSize * scale;
        final rect = Offset(
              (box.width - display.width) / 2,
              (box.height - display.height) / 2,
            ) &
            display;

        Offset pixelOf(Offset n) =>
            rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);

        return CustomPaint(
          size: box,
          painter: _LiveQuadPainter(
            points: [
              pixelOf(corners.topLeft),
              pixelOf(corners.topRight),
              pixelOf(corners.bottomRight),
              pixelOf(corners.bottomLeft),
            ],
            color: color,
          ),
        );
      },
    );
  }
}

class _LiveQuadPainter extends CustomPainter {
  final List<Offset> points;
  final Color color;

  const _LiveQuadPainter({required this.points, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length != 4) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(points[0].dx, points[0].dy)
      ..lineTo(points[1].dx, points[1].dy)
      ..lineTo(points[2].dx, points[2].dy)
      ..lineTo(points[3].dx, points[3].dy)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_LiveQuadPainter old) =>
      old.points != points || old.color != color;
}
