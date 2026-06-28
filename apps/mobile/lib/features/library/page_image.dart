/// One page's resolved image for the viewer. [imagePath] is ABSOLUTE (resolved
/// at read time via DocumentFileStore) — the widget layer never touches the
/// file store. Symmetric with DocumentSummary on the read side.
class PageImage {
  final int position;
  final String imagePath;
  const PageImage({required this.position, required this.imagePath});
}
