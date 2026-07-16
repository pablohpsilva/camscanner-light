import 'package:flutter/foundation.dart';

import '../../core/logging/app_logger.dart';

/// Guards an async action with a single busy flag + a double-run guard +
/// try/catch/finally, logging any failure via [AppLogger] instead of the
/// widget-layer's silent `catch (_)` (P06 task 1). A plain [ChangeNotifier]
/// (mirrors SaveController) so the orchestration is unit-testable WITHOUT
/// pumping a widget; the toast/mounted-check stay at the call site via
/// `context.showErrorSnack`.
class AsyncActionController extends ChangeNotifier {
  final AppLogger _logger;
  AsyncActionController({AppLogger logger = const PrintAppLogger()})
    : _logger = logger; // ignore: prefer_initializing_formals

  bool _busy = false;
  bool get busy => _busy;

  bool _lastActionFailed = false;

  /// Whether the most recent [run] threw (so the caller can show a toast).
  /// Reset to false at the start of each run.
  bool get lastActionFailed => _lastActionFailed;

  bool _disposed = false;

  /// Runs [action] guarded. Returns its result on success, or null when it is
  /// skipped (already busy / disposed) or throws. On a throw the error is
  /// LOGGED via [AppLogger] (never rethrown) and [lastActionFailed] is set.
  /// [busy] is true for the duration and cleared in a `finally`. [context]
  /// labels the log entry.
  Future<T?> run<T>(Future<T> Function() action, {String? context}) async {
    if (_disposed || _busy) return null;
    _lastActionFailed = false;
    _setBusy(true);
    try {
      return await action();
    } catch (e, st) {
      _lastActionFailed = true;
      _logger.error(e, stackTrace: st, context: context);
      return null;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (_disposed) return;
    _busy = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
