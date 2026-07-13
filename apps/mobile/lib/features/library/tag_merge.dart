/// Pure helper for bulk-tag's "add, never replace" semantics: the final tag
/// set for a document is the union of the tags it already has and the tags
/// chosen in the bulk-tag sheet. Extracted so the merge logic itself can be
/// unit-tested without driving the HomeScreen widget.
Set<int> mergeTagIds(Set<int> existing, Set<int> chosen) => {
  ...existing,
  ...chosen,
};
