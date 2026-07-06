import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Bundles files into a single zip archive. Injectable (DIP) so tests use a
/// recording fake instead of touching the filesystem. Mirrors [ShareChannel]:
/// a small, single-purpose channel that keeps its third-party dependency
/// ([archive]) from leaking into the rest of the app.
abstract interface class FileArchiver {
  /// Zips [files] into a single temp `.zip` named [archiveName] and returns it.
  /// [entryNames] gives the in-zip filename for each file (same length/order as
  /// [files]); colliding names are de-duplicated with a numeric suffix. The
  /// producer of [files] is responsible for their contents being share-safe.
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames});
}

/// Production archiver backed by the `archive` package. The only file in the
/// app that imports `archive`.
class SystemFileArchiver implements FileArchiver {
  const SystemFileArchiver();

  @override
  Future<File> zip(List<File> files,
      {required String archiveName, required List<String> entryNames}) async {
    final archive = Archive();
    final used = <String>{};
    for (var i = 0; i < files.length; i++) {
      final bytes = await files[i].readAsBytes();
      archive.addFile(ArchiveFile.bytes(_dedup(entryNames[i], used), bytes));
    }
    final encoded = ZipEncoder().encodeBytes(archive);
    final dir = await Directory.systemTemp.createTemp('zip_export');
    final file = File('${dir.path}/$archiveName');
    await file.writeAsBytes(encoded);
    return file;
  }

  /// Returns [name] if unused, else appends " (2)", " (3)", … before the
  /// extension until unique. Records the winner in [used].
  String _dedup(String name, Set<String> used) {
    if (used.add(name)) return name;
    final ext = p.extension(name);
    final stem = p.basenameWithoutExtension(name);
    for (var n = 2;; n++) {
      final candidate = '$stem ($n)$ext';
      if (used.add(candidate)) return candidate;
    }
  }
}
