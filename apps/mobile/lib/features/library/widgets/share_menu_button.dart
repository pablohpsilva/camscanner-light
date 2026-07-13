import 'package:flutter/material.dart';

/// SnackBar copy shown when link-share / fax are tapped but no real provider is
/// wired yet. Shared so tests and UI assert the same strings.
const String kLinkShareUnavailableMessage = "Link sharing isn't available yet";
const String kFaxUnavailableMessage = "Fax isn't available yet";

/// Menu values for the shared "extra" share actions.
const String kShareLinkValue = 'share-link';
const String kFaxValue = 'fax';

/// The shared Share-link (+ Fax unless [showFax] is false) menu entries.
/// [keyPrefix] namespaces the item keys so multiple menus stay unique
/// (e.g. 'document-42', 'page-viewer', 'share-menu').
List<PopupMenuEntry<String>> shareExtraMenuItems({
  required bool showFax,
  required String keyPrefix,
  bool showShareLink = true,
}) => [
  if (showShareLink)
    PopupMenuItem<String>(
      value: kShareLinkValue,
      key: Key('$keyPrefix-share-link'),
      child: const Text('Share link'),
    ),
  if (showFax)
    PopupMenuItem<String>(
      value: kFaxValue,
      key: Key('$keyPrefix-fax'),
      child: const Text('Fax'),
    ),
];

/// Handles a tap on a shared extra action. This release only ships the
/// not-available path: it shows the "…isn't available yet" SnackBar. When a real
/// LinkShareChannel/FaxProvider is wired, the available branch is added here
/// together with its UX (see spec non-goals).
void handleShareExtra(BuildContext context, String value) {
  final message = value == kFaxValue
      ? kFaxUnavailableMessage
      : kLinkShareUnavailableMessage;
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
    tooltip: 'Share',
    icon: const Icon(Icons.share),
    onSelected: (value) {
      if (value == 'share') {
        onShare();
      } else {
        handleShareExtra(context, value);
      }
    },
    itemBuilder: (_) => [
      const PopupMenuItem<String>(
        value: 'share',
        key: Key('share-menu-share'),
        child: Text('Share'),
      ),
      ...shareExtraMenuItems(
        showFax: showFax,
        showShareLink: showShareLink,
        keyPrefix: 'share-menu',
      ),
    ],
  );
}
