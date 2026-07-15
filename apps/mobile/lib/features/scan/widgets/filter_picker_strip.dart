import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../../l10n/l10n.dart';
import '../../library/auto_enhancer.dart';
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
// Grayscale. Each entry is (mode, fallback icon, tile key). The display label
// is resolved from [mode] in `build` (via `context.l10n`) since a const list
// can't hold a `BuildContext`-dependent value.
final _kFilters = [
  (
    mode: EnhancerMode.auto,
    icon: Icons.auto_fix_high,
    tileKey: 'filter-tile-auto',
  ),
  (
    mode: EnhancerMode.none,
    icon: Icons.image_outlined,
    tileKey: 'filter-tile-original',
  ),
  (
    mode: EnhancerMode.color,
    icon: Icons.color_lens_outlined,
    tileKey: 'filter-tile-color',
  ),
  (
    mode: EnhancerMode.grayscale,
    icon: Icons.filter_b_and_w_outlined,
    tileKey: 'filter-tile-grayscale',
  ),
];

/// Localized label for each [EnhancerMode] as shown in the filter strip.
/// Resolution happens in `build` (via `context.l10n`).
String _filterLabel(EnhancerMode mode, AppLocalizations l10n) => switch (mode) {
  EnhancerMode.auto => l10n.filterAuto,
  EnhancerMode.none => l10n.filterOriginal,
  EnhancerMode.color => l10n.filterColor,
  EnhancerMode.grayscale => l10n.filterGrayscale,
};

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
    // Bare set (this may be called from initState, where setState is illegal).
    // The first build reflects it; the `finally` below always clears it VIA
    // setState so the tiles never stay on a spinner forever.
    _generating = true;

    try {
      // Step 1: downsample in a compute isolate (avoids blocking UI thread).
      final small = await compute(_thumbFn, bytes);
      if (!mounted || small == null) return; // finally clears _generating

      // Step 2: apply all enhancers concurrently on the downsampled bytes.
      final results = await Future.wait([
        const AutoEnhancer().enhance(small),
        const NoneEnhancer().enhance(small),
        const ColorEnhancer().enhance(small),
        const GrayscaleEnhancer().enhance(small),
      ]);
      if (!mounted) return;
      _thumbs = {
        EnhancerMode.auto: results[0],
        EnhancerMode.none: results[1],
        EnhancerMode.color: results[2],
        EnhancerMode.grayscale: results[3],
      };
    } catch (_) {
      // Thumbnail generation failed (e.g. an enhancer threw on a degenerate
      // image). Leave [_thumbs] empty so the tiles fall back to their filter
      // icons — never an infinite spinner. Selecting a filter still works: the
      // accept path applies the enhancer to the full capture with its own
      // failure fallback.
    } finally {
      // Always settle: rebuild so tiles show either the generated thumbnails
      // (success) or their fallback icons (failure) instead of spinning.
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final l10n = context.l10n;
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
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Icon(f.icon, size: 28, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _filterLabel(f.mode, l10n),
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
