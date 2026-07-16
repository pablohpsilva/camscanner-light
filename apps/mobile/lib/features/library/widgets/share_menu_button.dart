import 'package:flutter/material.dart';
import '../../../l10n/l10n.dart';
import '../share/share_action.dart';

/// Menu values for the shared "extra" share actions.
const String kShareLinkValue = 'share-link';
const String kFaxValue = 'fax';

/// The shared Share-link (+ Fax unless [showFax] is false) menu entries, built
/// from the [ShareAction] model (P11) so the keys and labels have a single
/// source. Dispatch stays string-valued because these popups mix
/// share/rename/link/fax in one `PopupMenuButton<String>`; [showShareLink] /
/// [showFax] gate the two extras independently (a surface may pass raw booleans,
/// not a FeatureFlags). [keyPrefix] namespaces the item keys so multiple menus
/// stay unique (e.g. 'document-42', 'page-viewer', 'share-menu').
List<PopupMenuEntry<String>> shareExtraMenuItems({
  required BuildContext context,
  required bool showFax,
  required String keyPrefix,
  bool showShareLink = true,
}) {
  final l10n = context.l10n;
  bool included(ShareActionKind kind) =>
      kind == ShareActionKind.fax ? showFax : showShareLink;
  return [
    for (final action in const [
      ShareAction(ShareActionKind.shareLink),
      ShareAction(ShareActionKind.fax),
    ])
      if (included(action.kind))
        PopupMenuItem<String>(
          value: action.kind == ShareActionKind.fax
              ? kFaxValue
              : kShareLinkValue,
          key: action.keyFor(keyPrefix),
          child: Text(action.label(l10n)),
        ),
  ];
}

/// Handles a tap on a shared extra action. This release only ships the
/// not-available path: it shows the "…isn't available yet" SnackBar. When a real
/// LinkShareChannel/FaxProvider is wired, the available branch is added here
/// together with its UX (see spec non-goals).
void handleShareExtra(BuildContext context, String value) {
  final message = value == kFaxValue
      ? context.l10n.shareFaxUnavailable
      : context.l10n.shareLinkUnavailable;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

/// Standalone share menu for screens whose only share affordance was an
/// IconButton (pdf_preview, recognized_text). Share delegates to [onShare]
/// (the screen's existing behavior, verbatim); Share-link/Fax show the
/// not-available SnackBar via [handleShareExtra].
class ShareMenuButton extends StatelessWidget {
  final Key buttonKey;
  final VoidCallback onShare;
  final bool showFax;
  final bool showShareLink;
  final bool enabled;

  const ShareMenuButton({
    super.key,
    required this.buttonKey,
    required this.onShare,
    this.showFax = true,
    this.showShareLink = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    key: buttonKey,
    enabled: enabled,
    tooltip: context.l10n.commonShare,
    icon: const Icon(Icons.share),
    onSelected: (value) {
      if (value == 'share') {
        onShare();
      } else {
        handleShareExtra(context, value);
      }
    },
    itemBuilder: (menuContext) => [
      PopupMenuItem<String>(
        value: 'share',
        key: const Key('share-menu-share'),
        child: Text(context.l10n.commonShare),
      ),
      ...shareExtraMenuItems(
        context: menuContext,
        showFax: showFax,
        showShareLink: showShareLink,
        keyPrefix: 'share-menu',
      ),
    ],
  );
}
