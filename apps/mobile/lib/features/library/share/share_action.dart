import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../feature_flags.dart';

/// The distinct share / export actions the app can offer, declared in canonical
/// on-screen order. The page_viewer bottom sheet renders the full enabled set;
/// the documents-list-view and share-button popups render only the
/// [shareLink] / [fax] "extras" (see [shareExtras]) alongside their own generic
/// Share item.
///
/// P11 — this enum is the SINGLE source of truth for what a share action is
/// (its label, icon, key and gating flag), replacing three copy-pasted,
/// stringly-typed menu implementations.
enum ShareActionKind {
  exportPdf,
  shareImage,
  exportAllImages,
  print,
  protect,
  shareLink,
  fax,
}

/// One share action's presentation + gating data. A surface supplies its own
/// widget wrapper (`ListTile` vs `PopupMenuItem`) — the model provides the data
/// (label / icon / key / enabled), never the widget, so no surface is forced
/// into the wrong control.
class ShareAction {
  final ShareActionKind kind;
  const ShareAction(this.kind);

  /// The stable Key suffix, namespaced by a surface prefix via [keyFor]. These
  /// reproduce the historical menu keys EXACTLY (`page-viewer-export`,
  /// `document-42-share-link`, `share-menu-fax`, …) so every widget/BDD suite
  /// keeps matching.
  String get keySuffix => switch (kind) {
    ShareActionKind.exportPdf => 'export',
    ShareActionKind.shareImage => 'export-image',
    ShareActionKind.exportAllImages => 'export-all-images',
    ShareActionKind.print => 'print',
    ShareActionKind.protect => 'protect',
    ShareActionKind.shareLink => 'share-link',
    ShareActionKind.fax => 'fax',
  };

  Key keyFor(String prefix) => Key('$prefix-$keySuffix');

  IconData get icon => switch (kind) {
    ShareActionKind.exportPdf => Icons.picture_as_pdf,
    ShareActionKind.shareImage => Icons.image_outlined,
    ShareActionKind.exportAllImages => Icons.collections_outlined,
    ShareActionKind.print => Icons.print_outlined,
    ShareActionKind.protect => Icons.lock_outline,
    ShareActionKind.shareLink => Icons.link,
    ShareActionKind.fax => Icons.print,
  };

  String label(AppLocalizations l10n) => switch (kind) {
    ShareActionKind.exportPdf => l10n.viewerShareExportPdf,
    ShareActionKind.shareImage => l10n.viewerShareAsImage,
    ShareActionKind.exportAllImages => l10n.viewerShareAllAsImages,
    ShareActionKind.print => l10n.viewerSharePrint,
    ShareActionKind.protect => l10n.viewerShareProtect,
    ShareActionKind.shareLink => l10n.shareLink,
    ShareActionKind.fax => l10n.shareFax,
  };

  bool isEnabled(FeatureFlags f) => switch (kind) {
    ShareActionKind.exportPdf => f.exportPdf,
    ShareActionKind.shareImage => f.shareImage,
    ShareActionKind.exportAllImages => f.exportAllImages,
    ShareActionKind.print => f.print,
    ShareActionKind.protect => f.protectWithPassword,
    ShareActionKind.shareLink => f.shareLink,
    ShareActionKind.fax => f.fax,
  };
}

/// All share/export actions, in canonical on-screen order. Iterating this list
/// (never a hand-maintained sequence) is what keeps every surface's ordering
/// identical.
const List<ShareAction> kAllShareActions = [
  ShareAction(ShareActionKind.exportPdf),
  ShareAction(ShareActionKind.shareImage),
  ShareAction(ShareActionKind.exportAllImages),
  ShareAction(ShareActionKind.print),
  ShareAction(ShareActionKind.protect),
  ShareAction(ShareActionKind.shareLink),
  ShareAction(ShareActionKind.fax),
];

/// The enabled share actions for [f], in order — the page_viewer share sheet's
/// item list. (This is the plan's `overflowItems`.)
List<ShareAction> availableShareActions(FeatureFlags f) =>
    kAllShareActions.where((a) => a.isEnabled(f)).toList();

/// The two shared "extra" actions ([ShareActionKind.shareLink],
/// [ShareActionKind.fax]) that are enabled for [f] — the single source the
/// list-view / share-button popups build their extras from.
List<ShareAction> shareExtras(FeatureFlags f) => availableShareActions(f)
    .where(
      (a) =>
          a.kind == ShareActionKind.shareLink || a.kind == ShareActionKind.fax,
    )
    .toList();

/// The page_viewer Share toolbar button is shown only when the umbrella
/// [FeatureFlags.share] flag is on AND at least one sub-action is enabled — so
/// an empty share sheet can never be opened. `isNotEmpty` DERIVES this from the
/// filtered list, replacing the hand-written OR-chain that had to be kept in
/// sync with the seven per-item flag reads by hand.
bool shouldShowShareButton(FeatureFlags f) =>
    f.share && availableShareActions(f).isNotEmpty;
