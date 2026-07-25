import 'package:flutter/foundation.dart';

import 'handedness_store.dart';

/// Holds the active [Handedness] and persists changes through a
/// [HandednessStore]. Defaults to right-handed (primary Scan on the right)
/// when constructed without a stored value.
class HandednessController extends ChangeNotifier {
  final HandednessStore _store;
  Handedness _value;

  HandednessController({
    required this._store,
    Handedness initial = Handedness.right,
  }) : _value = initial;

  Handedness get value => _value;

  /// Loads the persisted choice; used when the controller is constructed
  /// synchronously (default wiring in runCamScannerApp). A never-chosen store
  /// (null) leaves the current value untouched (defaults to right).
  Future<void> load() async {
    final stored = await _store.load();
    if (stored == null || stored == _value) return;
    _value = stored;
    notifyListeners();
  }

  Future<void> setHandedness(Handedness handedness) async {
    if (handedness == _value) return;
    _value = handedness;
    notifyListeners();
    await _store.save(handedness);
  }
}
