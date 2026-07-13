import 'fake_library.dart';

/// Shared handle to the fake repository being built up by the "the library
/// has a document ..." seed steps, so a later "the library organize screen is
/// showing" step can pump [HomeScreen] against the SAME repository instance.
/// Mirrors folder_filter_bdd_state.dart / tag_filter_bdd_state.dart (same
/// host-BDD-vs-real-DB rationale: a real NativeDatabase hangs under
/// testWidgets' FakeAsync zone, so this scenario seeds an in-memory
/// [FakeDocumentRepository] instead).
FakeDocumentRepository? bddOrganizeRepo;

/// document name -> id, so later "move"/"tag" steps can look up the id of a
/// document seeded by an earlier step.
final Map<String, int> bddOrganizeDocIdsByName = {};

/// Resets the shared BDD state. Call from a teardown if scenarios ever run
/// back-to-back in the same isolate without a fresh top-level in each file.
void resetOrganizeActionsBddState() {
  bddOrganizeRepo = null;
  bddOrganizeDocIdsByName.clear();
}
