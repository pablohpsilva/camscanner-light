/// Immutable shape of a legal document. Mirrors the JSON schema in
/// libs/legal-content/src/schema.mjs — change one, change both.
class LegalDocument {
  final String title;
  final String effectiveDate;
  final String effectiveDateLabel;

  /// Empty for English; a "the English version prevails" notice otherwise.
  final String translationNotice;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.effectiveDateLabel,
    required this.translationNotice,
    required this.intro,
    required this.sections,
  });
}

class LegalSection {
  final String id;
  final String heading;
  final List<LegalBlock> body;
  const LegalSection(this.id, this.heading, this.body);
}

sealed class LegalBlock {
  const LegalBlock();
}

class LegalParagraph extends LegalBlock {
  final String text;
  const LegalParagraph(this.text);
}

class LegalBullets extends LegalBlock {
  final List<String> items;
  const LegalBullets(this.items);
}
