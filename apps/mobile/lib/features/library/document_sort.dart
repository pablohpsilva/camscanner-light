import 'document_summary.dart';

/// What to sort the library by. Pure presentation concern (D3) — never
/// persisted; HomeScreen holds it in session state.
enum SortCriterion { name, created, modified }

enum SortDirection { asc, desc }

/// An immutable (criterion, direction) pair. [initial] is today's behavior:
/// newest-created first.
class DocumentSort {
  final SortCriterion criterion;
  final SortDirection direction;
  const DocumentSort(this.criterion, this.direction);

  static const DocumentSort initial = DocumentSort(
    SortCriterion.created,
    SortDirection.desc,
  );

  @override
  bool operator ==(Object other) =>
      other is DocumentSort &&
      other.criterion == criterion &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(criterion, direction);

  @override
  String toString() => 'DocumentSort($criterion, $direction)';
}

/// Returns a new list ordered by [sort]. Never mutates [docs] (operates on a
/// copy, so an unmodifiable input is fine). Total: handles 0/1/n, never throws.
///
/// Name is compared case-insensitively (not SQLite's BINARY uppercase-first
/// order). Ties resolve deterministically and direction-independently:
/// newest createdAt first, then id ascending — so the list never jitters.
List<DocumentSummary> sortDocuments(
  List<DocumentSummary> docs,
  DocumentSort sort,
) {
  final copy = [...docs];
  copy.sort((a, b) {
    int primary;
    switch (sort.criterion) {
      case SortCriterion.name:
        primary = a.document.name.toLowerCase().compareTo(
          b.document.name.toLowerCase(),
        );
        break;
      case SortCriterion.created:
        primary = a.document.createdAt.compareTo(b.document.createdAt);
        break;
      case SortCriterion.modified:
        primary = a.document.modifiedAt.compareTo(b.document.modifiedAt);
        break;
    }
    if (sort.direction == SortDirection.desc) primary = -primary;
    if (primary != 0) return primary;
    // Deterministic, direction-independent tie-break.
    final byCreatedDesc = b.document.createdAt.compareTo(a.document.createdAt);
    if (byCreatedDesc != 0) return byCreatedDesc;
    return a.document.id.compareTo(b.document.id);
  });
  return copy;
}

/// The sort after the user taps [tapped]. Tapping the ACTIVE criterion flips
/// direction; tapping an INACTIVE one switches to it with its default
/// direction (name→asc, created→desc, modified→desc).
DocumentSort nextSort(DocumentSort current, SortCriterion tapped) {
  if (tapped == current.criterion) {
    final flipped = current.direction == SortDirection.asc
        ? SortDirection.desc
        : SortDirection.asc;
    return DocumentSort(current.criterion, flipped);
  }
  return DocumentSort(tapped, _defaultDirection(tapped));
}

SortDirection _defaultDirection(SortCriterion c) {
  switch (c) {
    case SortCriterion.name:
      return SortDirection.asc;
    case SortCriterion.created:
    case SortCriterion.modified:
      return SortDirection.desc;
  }
}
