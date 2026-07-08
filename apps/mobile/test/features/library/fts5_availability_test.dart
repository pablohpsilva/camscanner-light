import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Proves the host test runtime's SQLite has FTS5 + the trigram tokenizer.
/// Device is fine (sqlite3_flutter_libs ships FTS5); this guards the HOST path
/// that Tasks 2–3 rely on. If it fails, those tests move to integration_test/.
void main() {
  test('host SQLite supports fts5 trigram substring MATCH', () async {
    final db = NativeDatabase.memory();
    await db.ensureOpen(_NoOpUser());
    await db.runCustom(
        "CREATE VIRTUAL TABLE t USING fts5(x, tokenize = 'trigram')", const []);
    await db.runCustom("INSERT INTO t(rowid, x) VALUES (1, 'rescanned page')",
        const []);
    final rows =
        await db.runSelect("SELECT rowid FROM t WHERE t MATCH ?", ['scan']);
    expect(rows, hasLength(1),
        reason: 'trigram MATCH must find the mid-word substring "scan"');
    await db.close();
  });
}

class _NoOpUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;
  @override
  Future<void> beforeOpen(_, _) async {}
}
