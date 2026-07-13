import 'fake_library.dart';

/// Shared handle to the fake repository being built up by the "the library
/// has a document ... tagged ..." / "... with no tags" seed steps, so a later
/// "the library home screen is showing" step can pump [HomeScreen] against
/// the SAME repository instance. Mirrors folder_filter_bdd_state.dart (same
/// host-BDD-vs-real-DB rationale: a real NativeDatabase hangs under
/// testWidgets' FakeAsync zone, so this scenario seeds an in-memory
/// [FakeDocumentRepository] instead).
FakeDocumentRepository? bddTagRepo;

/// tag name -> id, so a second seed step reuses an already-created tag
/// instead of creating a duplicate with the same name.
final Map<String, int> bddTagIdsByName = {};

/// Resets the shared BDD state. Call from a teardown if scenarios ever run
/// back-to-back in the same isolate without a fresh top-level in each file.
void resetTagFilterBddState() {
  bddTagRepo = null;
  bddTagIdsByName.clear();
}
