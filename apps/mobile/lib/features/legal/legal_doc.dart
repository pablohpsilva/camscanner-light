/// The three legal documents, in the order they appear in Settings.
enum LegalDoc {
  terms('terms'),
  privacy('privacy'),
  faq('faq');

  const LegalDoc(this.key);

  /// Matches the `doc` field in libs/legal-content/content/*.json.
  final String key;
}
