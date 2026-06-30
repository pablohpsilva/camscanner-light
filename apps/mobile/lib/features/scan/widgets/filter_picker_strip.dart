import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../library/auto_enhancer.dart';
import '../../library/bw_enhancer.dart';
import '../../library/color_enhancer.dart';
import '../../library/enhancer_mode.dart';
import '../../library/grayscale_enhancer.dart';
import '../../library/image_enhancer.dart';

// Top-level: downsample to ≤150 px wide for thumbnail generation.
// Called via compute() — must be top-level, not a closure.
// Returns JPEG bytes (quality 85, display-only) or null on any failure.
Uint8List? _thumbFn(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final oriented = img.bakeOrientation(decoded);
    final w = oriented.width > 150 ? 150 : oriented.width;
    final h = (w * oriented.height / oriented.width).round();
    final small = img.copyResize(oriented, width: w, height: h);
    return Uint8List.fromList(img.encodeJpg(small, quality: 85));
  } catch (_) {
    return null;
  }
}

// Fixed display order: Auto first (it's the default), then Original, Color,
// Grayscale, B&W. Each entry is (mode, display label, fallback icon, tile key).
final _kFilters = [
  (
    mode: EnhancerMode.auto,
    label: 'Auto',
    icon: Icons.auto_fix_high,
    tileKey: 'filter-tile-auto',
  ),
  (
    mode: EnhancerMode.none,
    label: 'Original',
    icon: Icons.image_outlined,
    tileKey: 'filter-tile-original',
  ),
  (
    mode: EnhancerMode.color,
    label: 'Color',
    icon: Icons.color_lens_outlined,
    tileKey: 'filter-tile-color',
  ),
  (
    mode: EnhancerMode.grayscale,
    label: 'Grayscale',
    icon: Icons.filter_b_and_w_outlined,
    tileKey: 'filter-tile-grayscale',
  ),
  (
    mode: EnhancerMode.bw,
    label: 'B&W',
    icon: Icons.contrast,
    tileKey: 'filter-tile-bw',
  ),
];

class FilterPickerStrip extends StatefulWidget {
  final EnhancerMode selectedMode;
  final void Function(EnhancerMode) onModeChanged;
  final Uint8List? sourceBytes;

  const FilterPickerStrip({
    super.key,
    required this.selectedMode,
    required this.onModeChanged,
    this.sourceBytes,
  });

  @override
  State<FilterPickerStrip> createState() => _FilterPickerStripState();
}

class _FilterPickerStripState extends State<FilterPickerStrip> {
  Map<EnhancerMode, Uint8List?> _thumbs = {};
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _maybeGenerate(widget.sourceBytes);
  }

  @override
  void didUpdateWidget(FilterPickerStrip old) {
    super.didUpdateWidget(old);
    // Trigger generation the first time sourceBytes becomes available.
    if (old.sourceBytes == null && widget.sourceBytes != null) {
      _maybeGenerate(widget.sourceBytes);
    }
  }

  Future<void> _maybeGenerate(Uint8List? bytes) async {
    // Skip trivially short payloads — no valid image format fits in < 20 bytes.
    if (_generating || bytes == null || bytes.length < 20) return;
    _generating = true;

    // Step 1: downsample in a compute isolate (avoids blocking UI thread).
    final small = await compute(_thumbFn, bytes);
    if (!mounted || small == null) {
      _generating = false;
      return;
    }

    // Step 2: apply all 5 enhancers concurrently on the downsampled bytes.
    final results = await Future.wait([
      const AutoEnhancer().enhance(small),
      const NoneEnhancer().enhance(small),
      const ColorEnhancer().enhance(small),
      const GrayscaleEnhancer().enhance(small),
      const BwEnhancer().enhance(small),
    ]);

    if (!mounted) {
      _generating = false;
      return;
    }
    setState(() {
      _thumbs = {
        EnhancerMode.auto: results[0],
        EnhancerMode.none: results[1],
        EnhancerMode.color: results[2],
        EnhancerMode.grayscale: results[3],
        EnhancerMode.bw: results[4],
      };
    });
    _generating = false;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      height: 100,
      color: Colors.black,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        children: _kFilters.map((f) {
          final isSelected = f.mode == widget.selectedMode;
          final thumb = _thumbs[f.mode];
          return GestureDetector(
            onTap: () => widget.onModeChanged(f.mode),
            child: Container(
              key: Key(f.tileKey),
              width: 68,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                border: isSelected
                    ? Border.all(color: primary, width: 2)
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 52,
                    height: 60,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: thumb != null
                          ? Image.memory(thumb, fit: BoxFit.cover)
                          : _generating
                              ? const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                )
                              : Icon(f.icon, size: 28, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    f.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? Colors.white : Colors.white60,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
