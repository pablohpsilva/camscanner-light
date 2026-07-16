import 'dart:io';

import 'package:flutter/foundation.dart';

import '../scan/captured_image.dart';
import 'crop_corners.dart';
import 'document_printer.dart';
import 'document_repository.dart';
import 'enhancer_mode.dart';
import 'export/export_quality.dart';
import 'image_cache_invalidator.dart';
import 'image_enhancer.dart';
import 'page_image.dart';
import 'share_channel.dart';
import 'view_state.dart';

/// Owns the page-viewer's state + ALL repository orchestration (P06 tasks 5-8),
/// so the widget is a thin view: dialogs, navigation, l10n toasts, and
/// rendering only. A [ChangeNotifier] (mirrors SaveController) with a
/// [_disposed] guard, unit-testable without pumping a widget.
///
/// Load state is a [ViewState] (Loading/ErrorState/Empty/Loaded) — illegal
/// combinations of the old loose booleans are unrepresentable. [editing] and
/// [exporting] are orthogonal in-flight overlays. Every path that replaces the
/// page list clamps [current] so `pages[current]` can never go out of range.
class PageViewerController extends ChangeNotifier {
  final DocumentRepository _repository;
  final DocumentPrinter _printer;
  final ShareChannel _share;
  final ImageCacheInvalidator _invalidator;
  final int documentId;

  /// The `cacheWidth` the widget decodes the display image at (set from
  /// MediaQuery in build), so [reloadAfterEdit] can evict the exact
  /// ResizeImage variant, not just the bare FileImage (P13 task 1/2).
  int? displayCacheWidth;

  PageViewerController({
    required DocumentRepository repository,
    required this.documentId,
    required String name,
    DocumentPrinter printer = const SystemDocumentPrinter(),
    ShareChannel share = const SystemShareChannel(),
    ImageCacheInvalidator invalidator = const ScopedImageCacheInvalidator(),
  }) : _repository = repository, // ignore: prefer_initializing_formals
       _printer = printer, // ignore: prefer_initializing_formals
       _share = share, // ignore: prefer_initializing_formals
       _name = name, // ignore: prefer_initializing_formals
       _invalidator = invalidator; // ignore: prefer_initializing_formals

  ViewState<List<PageImage>> _state = const Loading();
  ViewState<List<PageImage>> get state => _state;

  /// The loaded pages, or empty when loading/error/empty.
  List<PageImage> get pages => switch (_state) {
    Loaded(:final data) => data,
    _ => const [],
  };

  String _name;
  String get name => _name;

  int _current = 0;
  int get current => _current;

  /// The currently-displayed page, or null when there are none.
  PageImage? get currentPage {
    final p = pages;
    return p.isEmpty ? null : p[_current.clamp(0, p.length - 1)];
  }

  int _imageEpoch = 0;
  int get imageEpoch => _imageEpoch;

  bool _editing = false;
  bool get editing => _editing;

  bool _exporting = false;
  bool get exporting => _exporting;

  bool _disposed = false;

  void setCurrent(int index) => _set(() => _current = index);

  // --- load / reload ---

  Future<void> load() async {
    _set(() => _state = const Loading());
    try {
      final loaded = await _repository.getDocumentPages(documentId);
      if (_disposed) return;
      _set(() => _setLoaded(loaded));
    } catch (_) {
      if (_disposed) return;
      _set(() => _state = const ErrorState('load'));
    }
  }

  /// Assigns the loaded pages, clamping [current] to a valid index (or 0 when
  /// empty) — the single choke point so `pages[current]` stays in range after a
  /// list shrinks (delete/split/merge).
  void _setLoaded(List<PageImage> loaded) {
    _current = loaded.isEmpty ? 0 : _current.clamp(0, loaded.length - 1);
    _state = loaded.isEmpty ? const Empty() : Loaded(loaded);
  }

  /// Evicts ONLY the edited page's cached image (scoped — not a global clear,
  /// P13), bumps the epoch (forces a fresh decode of a same-path regenerated
  /// flat), then reloads. Called before the reload, while [currentPage] still
  /// points at the just-edited page whose flat was regenerated at the same path.
  Future<void> reloadAfterEdit() async {
    final page = currentPage;
    if (page != null) {
      _invalidator.evict(page.displayPath, cacheWidth: displayCacheWidth);
    }
    _imageEpoch++;
    if (_disposed) return;
    await load();
  }

  // --- export / share (set the exporting overlay) ---

  /// Exports the document PDF; returns the file or null on failure (the widget
  /// navigates to the preview on success, toasts on null).
  Future<File?> exportPdf(ExportQuality quality) =>
      _guardExport(() => _repository.exportPdf(documentId, quality: quality));

  /// Exports the page at [position] as an image AND shares it. Returns whether
  /// it succeeded.
  Future<bool> exportPageAsImageAndShare(int position, ExportQuality quality) =>
      _guardExportBool(() async {
        final file = await _repository.exportPageAsImage(
          documentId,
          position,
          quality: quality,
        );
        await _share.share([file.path], subject: _name);
      });

  /// Exports every page as an image AND shares them. Returns success.
  Future<bool> exportAllImagesAndShare(ExportQuality quality) =>
      _guardExportBool(() async {
        final files = await _repository.exportAllPagesAsImages(
          documentId,
          quality: quality,
        );
        await _share.share(files.map((f) => f.path).toList(), subject: _name);
      });

  /// Builds the PDF and hands it to the printer. Returns success. (No exporting
  /// overlay — matches the original print action.)
  Future<bool> printDocument() async {
    try {
      final file = await _repository.exportPdf(documentId);
      await _printer.printPdf(file, name: _name);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Builds a password-protected PDF; returns the file or null on failure.
  Future<File?> protect(String password) async {
    try {
      return await _repository.exportProtectedPdf(documentId, password);
    } catch (_) {
      return null;
    }
  }

  /// Best-effort share (swallows failures, e.g. share unavailable in a host
  /// test) — used after [protect].
  Future<void> shareQuietly(File file) async {
    try {
      await _share.share([file.path], subject: _name);
    } catch (_) {
      /* share unavailable — ignore */
    }
  }

  Future<File?> _guardExport(Future<File> Function() action) async {
    _set(() => _exporting = true);
    try {
      return await action();
    } catch (_) {
      return null;
    } finally {
      if (!_disposed) _set(() => _exporting = false);
    }
  }

  Future<bool> _guardExportBool(Future<void> Function() action) async {
    _set(() => _exporting = true);
    try {
      await action();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) _set(() => _exporting = false);
    }
  }

  // --- document/page structural actions ---

  Future<bool> rename(String newName) async {
    try {
      final updated = await _repository.rename(documentId, newName);
      if (_disposed) return false;
      _set(() => _name = updated.name);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> deleteDocument() async {
    try {
      await _repository.deleteDocument(documentId);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Deletes the page at [position]. Returns the number of pages remaining (0 =>
  /// the document was deleted, so the widget pops), or null on failure. On a
  /// surviving document the list is reloaded (re-clamping [current]).
  Future<int?> deletePage(int position) async {
    try {
      final remaining = await _repository.deletePage(documentId, position);
      if (_disposed) return remaining;
      if (remaining > 0) await load();
      return remaining;
    } catch (_) {
      return null;
    }
  }

  Future<bool> splitAfter(int position) async {
    try {
      await _repository.splitAfter(documentId, position);
      if (_disposed) return true;
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> mergeInto(int sourceId) async {
    try {
      await _repository.mergeInto(documentId, sourceId);
      if (_disposed) return true;
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> replacePage(
    int position,
    CapturedImage image, {
    CropCorners? corners,
    ImageEnhancer? enhancer,
  }) async {
    try {
      await _repository.replacePage(
        documentId,
        position,
        image,
        corners: corners,
        enhancer: enhancer,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  // --- mutating edits (single-flight via the editing overlay) ---

  Future<bool> rotatePage(int position) =>
      _runEdit(() => _repository.rotatePage(documentId, position));

  Future<bool> updateCorners(int position, CropCorners corners) => _runEdit(
    () => _repository.updatePageCorners(documentId, position, corners),
  );

  Future<bool> updateEnhancer(int position, EnhancerMode mode) => _runEdit(
    () => _repository.updatePageEnhancer(documentId, position, mode),
  );

  /// Runs a single mutating [edit] with single-flight protection: refuses
  /// re-entry while another edit runs, flips [editing], reloads on success.
  /// Returns false only on an actual edit failure (a refused re-entry is a
  /// silent no-op returning true).
  Future<bool> _runEdit(Future<void> Function() edit) async {
    if (_editing) return true; // single-flight: refuse silently
    _set(() => _editing = true);
    try {
      await edit();
      if (_disposed) return true;
      await reloadAfterEdit();
      return true;
    } catch (_) {
      return false;
    } finally {
      if (!_disposed) _set(() => _editing = false);
    }
  }

  /// Optimistically reorders pages then persists. On persist failure the list
  /// is reloaded (rollback) and false is returned so the widget can toast. A
  /// reorder attempted mid-edit is refused (returns true, no-op).
  Future<bool> reorder(int oldIndex, int newIndex) async {
    if (_editing) return true;
    final current = pages;
    if (current.isEmpty) return true;
    final ordered = List<PageImage>.from(current);
    ordered.insert(newIndex, ordered.removeAt(oldIndex));
    _set(() {
      _state = Loaded(ordered); // optimistic, snappy UI
      _editing = true;
    });
    try {
      await _repository.reorderPages(
        documentId,
        ordered.map((p) => p.position).toList(),
      );
      return true;
    } catch (_) {
      if (_disposed) return false;
      await load(); // rollback to the persisted order
      return false;
    } finally {
      if (!_disposed) _set(() => _editing = false);
    }
  }

  void _set(void Function() mutate) {
    if (_disposed) return;
    mutate();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
