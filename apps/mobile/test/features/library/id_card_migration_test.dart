import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  test('schemaVersion is 6', () {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    expect(db.schemaVersion, 6);
  });

  test('fresh DB has the isIdCard column defaulting to false', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
          name: 'Doc',
          createdAt: DateTime.utc(2026, 7, 8),
          modifiedAt: DateTime.utc(2026, 7, 8),
        ));
    final row = await (db.select(db.documents)
          ..where((d) => d.id.equals(id)))
        .getSingle();
    expect(row.isIdCard, isFalse);
  });
}
