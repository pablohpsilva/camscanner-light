import 'fake_library.dart';

/// Shared handle to the fake repository being built up by the "the library
/// has a document ... in folder ..." / "... with no folder" seed steps, so a
/// later "the app launches ..." step can pump [HomeScreen] against the SAME
/// repository instance. Host-BDD steps (test/bdd/**) run under plain
/// `flutter test` (no IntegrationTestWidgetsFlutterBinding), where opening a
/// real NativeDatabase inside testWidgets' FakeAsync zone hangs indefinitely
/// (verified during Task 9 investigation — sqlite3 FFI I/O deadlocks under
/// the fake-async zone even wrapped in tester.runAsync). The existing
/// persistent-storage seed steps (a_document_was_saved_to_persistent_storage_
/// earlier.dart etc.) sidestep this because they are only ever exercised from
/// integration_test/ (a real device/emulator, real async zone). Folder
/// filtering's host-BDD scenario therefore seeds an in-memory
/// [FakeDocumentRepository] instead — same approach already used by every
/// other test/bdd/ scenario in this repo (e.g. the feedback BDD steps).
FakeDocumentRepository? bddFolderRepo;

/// folder name -> id, so a second seed step reuses an already-created folder
/// instead of creating a duplicate with the same name.
final Map<String, int> bddFolderIdsByName = {};

/// Resets the shared BDD state. Call from a teardown if scenarios ever run
/// back-to-back in the same isolate without a fresh top-level in each file
/// (bdd_widget_test gives each scenario its own testWidgets call, so this is
/// mostly a safety net).
void resetFolderFilterBddState() {
  bddFolderRepo = null;
  bddFolderIdsByName.clear();
}
