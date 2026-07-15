import 'dart:developer' as developer;

/// A minimal seam for reporting errors from anywhere in the app without
/// coupling callers to a concrete logging/printing mechanism.
///
/// Kept intentionally narrow (KISS): a single [error] method. Do not add
/// log levels such as `info`/`warn` here — add only what consumers need.
abstract class AppLogger {
  /// Reports [error], optionally with a [stackTrace] and free-form
  /// [context] describing where/why it occurred.
  void error(Object error, {StackTrace? stackTrace, String? context});
}

/// Production default [AppLogger]. Reports via `dart:developer`'s [log],
/// which is a no-op outside of an attached debugger/observatory, so it is
/// safe and silent in release builds. Never throws.
class PrintAppLogger implements AppLogger {
  const PrintAppLogger();

  @override
  void error(Object error, {StackTrace? stackTrace, String? context}) {
    try {
      developer.log(
        context == null ? '$error' : '$context: $error',
        name: 'AppLogger',
        error: error,
        stackTrace: stackTrace,
        level: 1000,
      );
    } catch (_) {
      // Logging must never throw or crash the caller.
    }
  }
}

/// A single recorded call to [SilentAppLogger.error].
class AppLoggerRecord {
  const AppLoggerRecord({required this.error, this.stackTrace, this.context});

  final Object error;
  final StackTrace? stackTrace;
  final String? context;
}

/// Test double [AppLogger] that records every call instead of reporting it,
/// so tests can assert on what was logged.
class SilentAppLogger implements AppLogger {
  final List<AppLoggerRecord> records = <AppLoggerRecord>[];

  @override
  void error(Object error, {StackTrace? stackTrace, String? context}) {
    records.add(
      AppLoggerRecord(error: error, stackTrace: stackTrace, context: context),
    );
  }
}
