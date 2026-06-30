import 'package:flutter/foundation.dart';

import '../scan/captured_image.dart';
import 'crop_corners.dart';
import 'document.dart';
import 'document_repository.dart';
import 'image_enhancer.dart';

enum SaveStatus { idle, saving, error }

/// Drives the review screen's Accept action. Mirrors `ScanController`: a small
/// state machine with a double-tap guard and dispose-safety. Holds no widgets.
class SaveController extends ChangeNotifier {
  final DocumentRepository _repository;
  SaveController({required DocumentRepository repository})
      : _repository = repository; // ignore: prefer_initializing_formals

  SaveStatus _status = SaveStatus.idle;
  SaveStatus get status => _status;
  bool get saving => _status == SaveStatus.saving;

  bool _disposed = false;

  /// Persists [image] with optional crop [corners] and [enhancer].
  /// Returns the saved [Document], or null on failure.
  Future<Document?> save(
    CapturedImage image, {
    CropCorners corners = CropCorners.fullFrame,
    ImageEnhancer enhancer = const NoneEnhancer(),
  }) async {
    if (_disposed || _status == SaveStatus.saving) return null;
    _set(SaveStatus.saving);
    try {
      final doc = await _repository.createFromCapture(image,
          corners: corners, enhancer: enhancer);
      if (_disposed) return null;
      _set(SaveStatus.idle);
      return doc;
    } catch (_) {
      if (_disposed) return null;
      _set(SaveStatus.error);
      return null;
    }
  }

  void _set(SaveStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
