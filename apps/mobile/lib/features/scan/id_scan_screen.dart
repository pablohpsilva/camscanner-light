import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import '../library/document_repository.dart';
import '../library/image_enhancer.dart';
import '../library/save_controller.dart';
import 'captured_image.dart';
import 'document_scanner_service.dart';
import 'scan_dependencies.dart';

/// Guided 2-step ID capture: scan the front, then the back, then save both as a
/// single ID-card document (front = page 1, back = page 2). No filter step.
class IdScanScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final DocumentRepository repository;

  const IdScanScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });

  @override
  State<IdScanScreen> createState() => _IdScanScreenState();
}

enum _Step { front, back, saving }

class _IdScanScreenState extends State<IdScanScreen> {
  late final DocumentScannerService _scanner;
  late final SaveController _saveController;
  _Step _step = _Step.front;

  @override
  void initState() {
    super.initState();
    _scanner = widget.dependencies.createDocumentScanner();
    _saveController = SaveController(repository: widget.repository);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final front = await _scanOne();
    if (!mounted) return;
    if (front == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.back);
    final back = await _scanOne();
    if (!mounted) return;
    if (back == null) {
      navigator.pop();
      return;
    }

    setState(() => _step = _Step.saving);
    const corners = CropCorners.fullFrame;
    const enhancer = NoneEnhancer();
    final doc = await _saveController.save(
      front,
      corners: corners,
      enhancer: enhancer,
    );
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save the ID. Try again.")),
      );
      navigator.pop();
      return;
    }
    final pos = await _saveController.addPage(
      back,
      doc.id,
      corners: corners,
      enhancer: enhancer,
    );
    if (!mounted) return;
    if (pos == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            "Saved the front, but the back failed. Retake it "
            "from the document.",
          ),
        ),
      );
      navigator.pop();
      return;
    }
    try {
      await widget.repository.markAsIdCard(doc.id);
    } catch (_) {
      // Non-fatal: the doc is saved; it just exports with the default layout.
    }
    if (mounted) navigator.pop();
  }

  /// One single-page scan; null when the user cancelled (empty result).
  Future<CapturedImage?> _scanOne() async {
    final pages = await _scanner.scan(pageLimit: 1);
    return pages.isEmpty ? null : pages.first;
  }

  @override
  void dispose() {
    _saveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_step) {
      _Step.front => 'Scan the FRONT of the ID',
      _Step.back => 'Scan the BACK of the ID',
      _Step.saving => 'Saving…',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Scan ID')),
      body: Center(
        key: const Key('id-scan-status'),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(label),
          ],
        ),
      ),
    );
  }
}
