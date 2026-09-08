import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../theme/app_colors.dart';
import '../../theme/widgets/app_back_header.dart';
import 'legal_content.dart';
import 'legal_doc.dart';
import 'legal_inline.dart';
import 'legal_models.dart';

/// Opens [uri] and returns whether it launched. Injectable — same seam shape
/// as `DonationUrlOpener` in `donation_screen.dart` — so link taps are
/// testable without the url_launcher platform channel.
typedef LegalUrlOpener = Future<bool> Function(Uri uri);

// externalApplication keeps the browser/mail app outside this app, matching
// the rest of the app's outbound-link convention.
Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Filenames content links to a sibling legal document with, e.g.
/// `[Privacy Policy](privacy.html)`. On the web these are rewritten per
/// locale and resolve; here they are relative URIs `launchUrl` cannot
/// resolve — `LaunchMode.externalApplication` hands the platform a bare
/// string like "privacy.html", which silently fails (no crash, no error,
/// just a dead link) in every locale. So these three names are intercepted
/// and pushed as an in-app [LegalDocumentScreen] instead of ever reaching
/// [LegalUrlOpener]. Everything else (`mailto:`, `https:`, ...) still goes
/// through the opener unchanged.
const Map<String, LegalDoc> _siblingDocs = {
  'terms.html': LegalDoc.terms,
  'privacy.html': LegalDoc.privacy,
  'faq.html': LegalDoc.faq,
};

/// Renders one of the three legal documents (Terms, Privacy, FAQ). No
/// `FEATURE_*` flag gates this screen — Apple and Google require the privacy
/// policy to stay reachable regardless of other build flags.
class LegalDocumentScreen extends StatelessWidget {
  const LegalDocumentScreen({
    super.key,
    required this.doc,
    this.openUrl = _launchExternal,
  });

  final LegalDoc doc;
  final LegalUrlOpener openUrl;

  static Route<void> route(LegalDoc doc, {LegalUrlOpener? openUrl}) =>
      MaterialPageRoute<void>(
        builder: (_) => openUrl == null
            ? LegalDocumentScreen(doc: doc)
            : LegalDocumentScreen(doc: doc, openUrl: openUrl),
      );

  void _handleLink(BuildContext context, String url) {
    final sibling = _siblingDocs[url];
    if (sibling != null) {
      Navigator.of(context).push(LegalDocumentScreen.route(sibling, openUrl: openUrl));
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null) openUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    final document = legalDocument(doc, Localizations.localeOf(context));
    return Scaffold(
      backgroundColor: r.paper,
      appBar: AppBackHeader(
        title: document.title,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${document.effectiveDateLabel}: ${document.effectiveDate}',
            style: TextStyle(fontFamily: 'Figtree', fontSize: 13, color: r.muted),
          ),
          if (document.translationNotice.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              key: const Key('legal-translation-notice'),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: r.amberSoft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: r.amber),
              ),
              child: Text(
                document.translationNotice,
                style: TextStyle(
                  fontFamily: 'Figtree',
                  fontSize: 12.5,
                  height: 1.5,
                  color: r.ink2,
                ),
              ),
            ),
          ],
          if (document.intro.isNotEmpty) ...[
            const SizedBox(height: 16),
            _LegalParagraph(
              text: document.intro,
              onLink: (url) => _handleLink(context, url),
              linkColor: r.blue,
              textColor: r.ink2,
            ),
          ],
          const SizedBox(height: 8),
          for (final section in document.sections)
            _LegalSection(
              doc: doc,
              section: section,
              onLink: (url) => _handleLink(context, url),
            ),
        ],
      ),
    );
  }
}

/// One document section. `LegalDoc.faq` renders as a collapsed
/// [ExpansionTile] (`heading` = question, `body` = answer); `terms` and
/// `privacy` render heading + blocks flat.
class _LegalSection extends StatelessWidget {
  const _LegalSection({required this.doc, required this.section, required this.onLink});

  final LegalDoc doc;
  final LegalSection section;
  final void Function(String url) onLink;

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    final headingStyle = TextStyle(
      fontFamily: 'Figtree',
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: r.ink,
    );
    final blocks = [
      for (final block in section.body) ...[
        _LegalBlockView(block: block, onLink: onLink, linkColor: r.blue, textColor: r.ink2),
        const SizedBox(height: 8),
      ],
    ];

    if (doc == LegalDoc.faq) {
      return ExpansionTile(
        key: Key('legal-section-${section.id}'),
        title: Text(section.heading, style: headingStyle),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      );
    }

    return Padding(
      key: Key('legal-section-${section.id}'),
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.heading, style: headingStyle),
          const SizedBox(height: 8),
          ...blocks,
        ],
      ),
    );
  }
}

class _LegalBlockView extends StatelessWidget {
  const _LegalBlockView({
    required this.block,
    required this.onLink,
    required this.linkColor,
    required this.textColor,
  });

  final LegalBlock block;
  final void Function(String url) onLink;
  final Color linkColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      LegalParagraph(:final text) => _LegalParagraph(
        text: text,
        onLink: onLink,
        linkColor: linkColor,
        textColor: textColor,
      ),
      LegalBullets(:final items) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('•  ', style: TextStyle(fontFamily: 'Figtree', fontSize: 14.5, color: textColor)),
                  Expanded(
                    child: _LegalParagraph(
                      text: item,
                      onLink: onLink,
                      linkColor: linkColor,
                      textColor: textColor,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    };
  }
}

/// Renders one paragraph of markup ([parseLegalInline]) as `Text.rich`, with
/// bold spans at `FontWeight.w700` and link spans in [linkColor] wired to a
/// [TapGestureRecognizer]. A [StatefulWidget] so every recognizer it creates
/// is disposed — an undisposed `TapGestureRecognizer` fails widget tests with
/// a leaked-recognizer report.
class _LegalParagraph extends StatefulWidget {
  const _LegalParagraph({
    required this.text,
    required this.onLink,
    required this.linkColor,
    required this.textColor,
  });

  final String text;
  final void Function(String url) onLink;
  final Color linkColor;
  final Color textColor;

  @override
  State<_LegalParagraph> createState() => _LegalParagraphState();
}

class _LegalParagraphState extends State<_LegalParagraph> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final baseStyle = TextStyle(
      fontFamily: 'Figtree',
      fontSize: 14.5,
      height: 1.55,
      color: widget.textColor,
    );
    final children = <InlineSpan>[];
    for (final span in parseLegalInline(widget.text)) {
      if (span.url != null) {
        final recognizer = TapGestureRecognizer()..onTap = () => widget.onLink(span.url!);
        _recognizers.add(recognizer);
        // A link gets its own inline widget (WidgetSpan) rather than sharing
        // the paragraph's single RenderParagraph. Two reasons: it keeps the
        // recognizer's hit box exactly the size of its own text — a merged
        // multi-line, multi-link TextSpan tree hit-tests correctly for a
        // real fingertip (glyph-precise), but `WidgetTester.tap` targets the
        // *whole* matched widget's bounding-box center, which for a long
        // wrapped paragraph can land on neither link — and it also gives the
        // link a distinct, exact-text `Text` widget that `find.textContaining`
        // can match on its own, instead of matching the whole paragraph.
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Text.rich(
              TextSpan(
                text: span.text,
                style: baseStyle.copyWith(
                  color: widget.linkColor,
                  decoration: TextDecoration.underline,
                ),
                recognizer: recognizer,
              ),
            ),
          ),
        );
      } else {
        children.add(
          TextSpan(
            text: span.text,
            style: span.bold ? const TextStyle(fontWeight: FontWeight.w700) : null,
          ),
        );
      }
    }
    return Text.rich(TextSpan(style: baseStyle, children: children));
  }
}
