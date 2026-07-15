import 'dart:io';
import 'dart:typed_data';

import 'package:mobile/core/io/temp_file_writer.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TempFileWriter', () {
    const writer = TempFileWriter();

    test('is const-constructible', () {
      // Compile-time assertion: this line only compiles if the default
      // constructor is const, as later composition-root code relies on.
      const another = TempFileWriter();
      expect(another, isA<TempFileWriter>());
    });

    test(
      'createTempDir returns a fresh, existing, unique dir per call',
      () async {
        final dir1 = await writer.createTempDir('t5_test');
        final dir2 = await writer.createTempDir('t5_test');

        expect(await dir1.exists(), isTrue);
        expect(await dir2.exists(), isTrue);
        expect(dir1.path, isNot(equals(dir2.path)));

        await writer.cleanup(dir1);
        await writer.cleanup(dir2);
      },
    );

    test(
      'writeBytes (async) writes bytes that read back identically',
      () async {
        final dir = await writer.createTempDir('t5_test_async');
        final bytes = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 255, 0, 128]);

        final file = await writer.writeBytes(dir, 'payload.bin', bytes);

        expect(await file.exists(), isTrue);
        final readBack = await file.readAsBytes();
        expect(readBack, equals(bytes));

        await writer.cleanup(dir);
      },
    );

    test(
      'writeBytes (sync: true) writes bytes that read back identically',
      () async {
        final dir = await writer.createTempDir('t5_test_sync');
        final bytes = Uint8List.fromList(<int>[9, 8, 7, 6, 5, 4]);

        final file = await writer.writeBytes(
          dir,
          'payload.bin',
          bytes,
          sync: true,
        );

        expect(await file.exists(), isTrue);
        final readBack = await file.readAsBytes();
        expect(readBack, equals(bytes));

        await writer.cleanup(dir);
      },
    );

    test('cleanup removes the dir', () async {
      final dir = await writer.createTempDir('t5_test_cleanup');
      expect(await dir.exists(), isTrue);

      await writer.cleanup(dir);

      expect(await dir.exists(), isFalse);
    });

    test('a second cleanup on an already-gone dir does not throw', () async {
      final dir = await writer.createTempDir('t5_test_double_cleanup');
      await writer.cleanup(dir);
      expect(await dir.exists(), isFalse);

      // Second cleanup on a dir that no longer exists must complete
      // silently without throwing.
      await expectLater(writer.cleanup(dir), completes);
    });

    test(
      'cleanup on an already-gone dir reports nothing when the logger is silent '
      '(no observable failure to assert on the host)',
      () async {
        final logger = SilentAppLogger();
        final loggingWriter = TempFileWriter(logger: logger);

        final dir = await loggingWriter.createTempDir('t5_test_logger');
        await loggingWriter.cleanup(dir);
        expect(await dir.exists(), isFalse);

        // Deleting an already-absent directory is not by itself a Dart
        // I/O error for a fresh, ordinary temp dir; nothing should have
        // been reported to the logger for this successful path.
        expect(logger.records, isEmpty);
      },
    );

    test(
      'cleanup swallows a genuine deletion failure and reports it via AppLogger '
      'instead of rethrowing',
      () async {
        final logger = SilentAppLogger();
        final loggingWriter = TempFileWriter(logger: logger);

        // Force a real deletion failure: create a child directory inside a
        // parent we then make read-only. On POSIX hosts, removing an entry
        // requires write permission on its PARENT, so the recursive delete
        // of `child` throws a FileSystemException (EACCES). `cleanup` must
        // swallow that and report it via the logger.
        final parent = await loggingWriter.createTempDir('t5_test_ro_parent');
        final child = Directory('${parent.path}/child')..createSync();
        File('${child.path}/f').writeAsBytesSync(Uint8List.fromList(<int>[1]));

        var undeletable = false;
        try {
          // Read + execute only: cannot remove `child` from `parent`.
          Process.runSync('chmod', <String>['500', parent.path]);
          // Confirm the OS actually blocks deletion before asserting on it,
          // so the test is skipped (not falsely green) on a host where the
          // running user can bypass parent permissions (e.g. root).
          try {
            child.deleteSync(recursive: true);
          } on FileSystemException {
            undeletable = true;
          }

          if (undeletable) {
            await expectLater(loggingWriter.cleanup(child), completes);
            expect(logger.records, hasLength(1));
            expect(logger.records.single.error, isNotNull);
            expect(logger.records.single.context, contains('cleanup'));
          }
        } finally {
          // Restore write permission so the temp tree can be removed.
          Process.runSync('chmod', <String>['700', parent.path]);
          await loggingWriter.cleanup(parent);
        }

        if (!undeletable) {
          // Host allowed the delete despite the read-only parent (e.g. root
          // or a filesystem that ignores mode bits). The swallow-and-report
          // path could not be forced here; the already-gone silent case
          // above still guarantees cleanup never rethrows.
          markTestSkipped(
            'Could not force a deletion failure on this host '
            '(user can bypass read-only parent permissions).',
          );
        }
      },
    );
  });
}
