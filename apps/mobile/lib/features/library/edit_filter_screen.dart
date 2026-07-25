import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../scan/widgets/filter_picker_strip.dart';
import 'enhancer_for_mode.dart';
import 'enhancer_mode.dart';
import 'image_enhancer.dart';
import 'preview_proxy.dart';
import 'widgets/editor_top_bar.dart';

Future<Uint8List> _defaultReadBytes(String path) => File(path).readAsBytes();

/// Full-screen filter editor. Shows the page's PRISTINE base image with the
/// scan-review filter strip (Auto / Original / Color / Grayscale). Save pops
/// the chosen [EnhancerMode]; back/cancel pops null. The chosen mode is applied
/// non-destructively by the caller (regenerating the flat from the base).
class EditFilterScreen extends StatefulWidget {
  final String imagePath;
  final EnhancerMode initialMode;

  /// B3 live-preview seams (see [CaptureReviewScreen]). [readBytes] loads the
  /// pristine base (defaults to `File(imagePath).readAsBytes()`);
  /// [previewDebounce] coalesces rapid switches; [proxyRunner] downsizes to a
  /// preview proxy (defaults to `compute(previewProxyJpeg, …)`); [previewEnhancerFor]
  /// maps a mode to the ON-SCREEN preview enhancer (defaults to
  /// [enhancerForMode]). Save is unaffected — it still pops the chosen [_mode].
  final Future<Uint8List> Function(String path) readBytes;
  final Duration previewDebounce;
  final Future<Uint8List> Function(Uint8List bytes)? proxyRunner;
  final ImageEnhancer Function(EnhancerMode mode)? previewEnhancerFor;

  const EditFilterScreen({
    super.key,
    required this.imagePath,
    required this.initialMode,
    this.readBytes = _defaultReadBytes,
    this.previewDebounce = const Duration(milliseconds: 250),
    this.proxyRunner,
    this.previewEnhancerFor,
  });

  @override
  State<EditFilterScreen> createState() => _EditFilterScreenState();
}

class _EditFilterScreenState extends State<EditFilterScreen> {
  late EnhancerMode _mode = widget.initialMode;
  Uint8List? _sourceBytes;

  // B3 live preview: the enhanced proxy shown on the big image, or null to show
  // the raw base (Original / not-yet-computed). Generation counter discards
  // stale async results; debounce timer coalesces rapid switches.
  Uint8List? _previewBytes;
  bool _previewComputing = false;
  Timer? _previewDebounce;
  int _previewGen = 0;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadSource() async {
    try {
      final b = await widget.readBytes(widget.imagePath);
      if (!mounted) return;
      setState(() => _sourceBytes = b);
    } catch (_) {
      // Non-loadable path (e.g. host tests) — strip falls back to icons.
    }
  }

  void _onModeChanged(EnhancerMode mode) {
    setState(() => _mode = mode);
    _schedulePreview(mode);
  }

  void _schedulePreview(EnhancerMode mode) {
    _previewDebounce?.cancel();
    final gen = ++_previewGen; // invalidate any in-flight compute
    if (mode == EnhancerMode.none) {
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
      final proxyRun = widget.proxyRunner ?? ((b) => compute(previewProxyJpeg, b));
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
      if (mounted && gen == _previewGen) {
        setState(() {
          _previewBytes = null;
          _previewComputing = false;
        });
      }
    }
  }

  // B3: show the enhanced live preview when available, else the raw base.
  // Both keep the `edit-filter-image` key so tests can find either.
  Widget _imageWidget() {
    final preview = _previewBytes;
    if (preview != null) {
      return Image.memory(
        preview,
        key: const Key('edit-filter-image'),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }
    return Image.file(
      File(widget.imagePath),
      key: const Key('edit-filter-image'),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Theme(
      data: AppTheme.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: EditorTopBar(
          title: l10n.editFilterTitle,
          onBack: () => Navigator.of(context).pop(),
          trailing: TextButton(
            key: const Key('edit-filter-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.commonCancel),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(child: Center(child: _imageWidget())),
                  // B3: small spinner while the live preview is being computed.
                  if (_previewComputing)
                    const Positioned(
                      top: 12,
                      right: 12,
                      child: SizedBox(
                        key: Key('edit-filter-preview-loading'),
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                ],
              ),
            ),
            FilterPickerStrip(
              key: const Key('filter-picker-strip'),
              selectedMode: _mode,
              onModeChanged: _onModeChanged,
              sourceBytes: _sourceBytes,
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('edit-filter-save'),
                    onPressed: () => Navigator.of(context).pop(_mode),
                    child: Text(l10n.commonSave),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
