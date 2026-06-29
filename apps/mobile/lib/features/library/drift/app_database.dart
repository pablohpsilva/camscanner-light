import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// One scanned document's metadata. Image bytes live on disk (see Pages); this
/// table holds only metadata. `createdAt`/`modifiedAt` are stored UTC.
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
}

/// One page of a document. B1 creates exactly one page (position 1). The image
/// path is RELATIVE to the app documents dir (resolved at read time) — never
/// absolute (iOS container GUID changes on reinstall/update).
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get relativeImagePath => text()();

  /// Normalized crop quad (E1) as "x0,y0,...,x3,y3"; null = uncropped (full
  /// frame). See CropCorners.
  TextColumn get corners => text().nullable()();
}

@DriftDatabase(tables: [Documents, Pages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(pages, pages.corners);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

/// Production opener — lazily opens the SQLite file in a background isolate.
LazyDatabase openAppDatabase(File file) =>
    LazyDatabase(() async => NativeDatabase.createInBackground(file));
