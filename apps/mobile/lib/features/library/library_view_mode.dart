/// How the library body lays out documents. In-memory session state only
/// (never persisted): the library opens in [list] and the user can toggle to
/// [grid] via the header's view toggle.
///
/// [toString] returns the bare value name (`list`/`grid`) so a
/// [ReamSegmented] built over these values keys its segments `segment-list` /
/// `segment-grid` (it uses `'segment-${value}'`).
enum LibraryViewMode {
  list,
  grid;

  @override
  String toString() => name;
}
