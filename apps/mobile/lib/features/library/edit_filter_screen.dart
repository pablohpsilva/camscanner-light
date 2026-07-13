import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../theme/ream_theme.dart';
import '../scan/widgets/filter_picker_strip.dart';
import 'enhancer_mode.dart';
import 'widgets/editor_top_bar.dart';

/// Full-screen filter editor. Shows the page's PRISTINE base image with the
/// scan-review filter strip (Auto / Original / Color / Grayscale). Save pops
/// the chosen [EnhancerMode]; back/cancel pops null. The chosen mode is applied
/// non-destructively by the caller (regenerating the flat from the base).
class EditFilterScreen extends StatefulWidget {
  final String imagePath;
  final EnhancerMode initialMode;

  const EditFilterScreen({
    super.key,
    required this.imagePath,
    required this.initialMode,
  });

  @override
  State<EditFilterScreen> createState() => _EditFilterScreenState();
}

class _EditFilterScreenState extends State<EditFilterScreen> {
  late EnhancerMode _mode = widget.initialMode;
  Uint8List? _sourceBytes;

  @override
  void initState() {
    super.initState();
    _loadSource();
  }

  Future<void> _loadSource() async {
    try {
      final b = await File(widget.imagePath).readAsBytes();
      if (mounted) setState(() => _sourceBytes = b);
    } catch (_) {
      // Non-loadable path (e.g. host tests) — strip falls back to icons.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ReamTheme.dark(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: EditorTopBar(
          title: 'Filter',
          onBack: () => Navigator.of(context).pop(),
          trailing: TextButton(
            key: const Key('edit-filter-cancel'),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Center(
                child: Image.file(
                  File(widget.imagePath),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox.shrink(),
                ),
              ),
            ),
            FilterPickerStrip(
              key: const Key('filter-picker-strip'),
              selectedMode: _mode,
              onModeChanged: (m) => setState(() => _mode = m),
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
                    child: const Text('Save'),
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
