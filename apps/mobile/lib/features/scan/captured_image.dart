/// One captured page: the path to its image file in temporary storage.
///
/// A3 produces this and hands it to the review screen. Persistence (B1) and
/// multi-page grouping (Feature 06) consume it later. Holds no bytes — the file
/// at [path] is the source of truth.
class CapturedImage {
  final String path;
  const CapturedImage(this.path);
}
