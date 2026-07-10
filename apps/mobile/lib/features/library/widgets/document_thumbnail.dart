import 'dart:io';

import 'package:flutter/material.dart';

/// A small, upright document thumbnail. Renders the stored JPEG via [Image.file]
/// with [cacheWidth] so the codec downsamples at decode (low memory). The stored
/// file keeps its EXIF Orientation tag, which Flutter honors — so it shows
/// upright with no re-encode. A null or unreadable path degrades to a neutral
/// placeholder (never a crash, never a host-test hang).
class DocumentThumbnail extends StatelessWidget {
  final String? path;
  final double size;
  const DocumentThumbnail({super.key, required this.path, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      width: size,
      height: size,
      color: scheme.surfaceContainerHighest,
      child: Icon(Icons.description_outlined, color: scheme.onSurfaceVariant),
    );

    final path = this.path;
    if (path == null) return placeholder;

    final dpr = MediaQuery.of(context).devicePixelRatio;
    // [size] may be double.infinity (e.g. the grid card fills its cell); in
    // that case the decode target is unknown, so skip cacheWidth rather than
    // feed Image.file a non-finite value (Infinity.toInt() throws).
    final targetWidth = size.isFinite ? (size * dpr).round() : null;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.file(
        File(path),
        width: size.isFinite ? size : null,
        height: size.isFinite ? size : null,
        fit: BoxFit.cover,
        cacheWidth: targetWidth,
        errorBuilder: (context, error, stack) => placeholder,
      ),
    );
  }
}
