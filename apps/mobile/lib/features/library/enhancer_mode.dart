/// Enhancement filter modes for the scan pipeline.
enum EnhancerMode {
  none,
  grayscale,
  auto,
  color;

  /// Bounds-checked int → [EnhancerMode] decode. An out-of-range or negative
  /// [index] (e.g. a stored value from a future schema) falls back to [none].
  /// Single source of truth for decoding a persisted enhancer-mode column.
  static EnhancerMode fromIndex(int index) =>
      (index >= 0 && index < values.length) ? values[index] : none;
}
