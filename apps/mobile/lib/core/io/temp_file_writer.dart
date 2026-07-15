import 'dart:io';
import 'dart:typed_data';

import '../logging/app_logger.dart';

/// Owns the "create a unique temp directory, write bytes into it, then clean
/// it up best-effort" pattern that is otherwise duplicated across the app's
/// export/OCR call sites.
///
/// Kept intentionally minimal (KISS): three methods, no mutable state, and a
/// `const` constructor so a composition root can default it as
/// `const TempFileWriter()`.
class TempFileWriter {
  /// Creates a writer. The logger receives best-effort [cleanup] failures and
  /// defaults to [PrintAppLogger] so production callers need not supply one.
  const TempFileWriter({AppLogger logger = const PrintAppLogger()})
    : _logger = logger; // ignore: prefer_initializing_formals

  final AppLogger _logger;

  /// Creates a fresh, unique temporary directory named with [prefix].
  ///
  /// Each call returns a distinct directory (delegates to
  /// [Directory.systemTemp.createTemp]).
  Future<Directory> createTempDir(String prefix) {
    return Directory.systemTemp.createTemp(prefix);
  }

  /// Writes [bytes] to `<dir>/<name>` and returns the resulting [File].
  ///
  /// When [sync] is true, uses [File.writeAsBytesSync]; otherwise the async
  /// [File.writeAsBytes]. The [sync] option exists so a later adopter can
  /// migrate off synchronous writes deliberately.
  Future<File> writeBytes(
    Directory dir,
    String name,
    Uint8List bytes, {
    bool sync = false,
  }) async {
    final file = File('${dir.path}/$name');
    if (sync) {
      file.writeAsBytesSync(bytes);
    } else {
      await file.writeAsBytes(bytes);
    }
    return file;
  }

  /// Deletes [dir] recursively, best-effort.
  ///
  /// If the directory is already gone, this completes without error. Any
  /// deletion failure is reported via the injected [AppLogger] and is never
  /// rethrown.
  Future<void> cleanup(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      _logger.error(
        error,
        stackTrace: stackTrace,
        context: 'TempFileWriter.cleanup failed for ${dir.path}',
      );
    }
  }
}
