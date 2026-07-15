import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';
import '../support/persistent_storage.dart';

/// Usage: the app is launched with camera permission granted and empty persistent storage
///
/// Like the plain empty-storage launch step, but backed by an on-disk SQLite
/// file + documents dir shared through [persistentDbFile]/[persistentDir], so
/// a later "the app launches reading that same storage" step can re-open the
/// SAME storage and prove persistence across a relaunch. Seeds NO documents.
Future<void>
theAppIsLaunchedWithCameraPermissionGrantedAndEmptyPersistentStorage(
  WidgetTester tester,
) async {
  final dir = await Directory.systemTemp.createTemp('v1persist');
  persistentDir = dir;
  persistentDbFile = File('${dir.path}/camscanner.sqlite');

  addTearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: persistentLibraryDependencies(
      dbFile: persistentDbFile!,
      baseDir: persistentDir!,
    ),
  );
  await tester.pumpAndSettle();
}
