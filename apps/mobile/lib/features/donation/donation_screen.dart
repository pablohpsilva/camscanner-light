import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../../core/ui/error_snack.dart';
import '../../theme/widgets/app_action_button.dart';
import '../../theme/widgets/app_back_header.dart';
import 'donation_availability.dart';
import 'donation_config.dart';
import 'tip_jar/storekit_tip_jar_service.dart';
import 'tip_jar/tip_jar_body.dart';
import 'tip_jar/tip_jar_service.dart';

/// Opens [uri] and returns whether it launched. Injectable (P07 SOC-1) so the
/// Ko-fi launch-refused / launch-threw branches are testable without the
/// url_launcher platform channel.
typedef DonationUrlOpener = Future<bool> Function(Uri uri);

/// Writes [text] to the clipboard. Injectable so the copy branch is testable
/// without the clipboard platform channel.
typedef DonationClipboardWriter = Future<void> Function(String text);

// externalApplication keeps payment outside the app (App Store 3.1.1).
Future<bool> _launchExternal(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);
Future<void> _writeClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));

TipJarService _defaultTipJar() => StoreKitTipJarService();

/// Full-screen donation page. Ko-fi opens in the external browser (store-safe:
/// no in-app payment collection); Bitcoin is display-only (QR + copyable
/// address). Sections hide when their config value is empty. A prominent
/// disclaimer states donations grant no benefits.
class DonationScreen extends StatelessWidget {
  const DonationScreen({
    super.key,
    this.kofiUrl = DonationConfig.kofiUrl,
    this.bitcoinAddress = DonationConfig.bitcoinAddress,
    this.openUrl = _launchExternal,
    this.copyToClipboard = _writeClipboard,
    this.createTipJar = _defaultTipJar,
    this.tipJarMode,
    this.iosBtcDonation = const bool.fromEnvironment(
      'FEATURE_IOS_BTC_DONATION',
      defaultValue: true,
    ),
  });

  final String kofiUrl;
  final String bitcoinAddress;

  /// URL-open / clipboard seams — production defaults call `launchUrl` /
  /// `Clipboard.setData`, byte-behaviour-identical to the old inline versions.
  final DonationUrlOpener openUrl;
  final DonationClipboardWriter copyToClipboard;

  /// Builds the tip-jar service (iOS). Injectable for tests.
  final TipJarService Function() createTipJar;

  /// Force tip-jar (`true`) or Ko-fi/BTC (`false`) body. `null` → platform
  /// default (`tipJarAvailable`). Tests pass an explicit value.
  final bool? tipJarMode;

  /// Whether the iOS tip-jar body also shows the display-only Bitcoin section
  /// (QR + copyable address) after the tip consumables. Defaults to the
  /// `FEATURE_IOS_BTC_DONATION` build flag (on). Bitcoin is display-only, so it
  /// carries no App Store 3.1.1 in-app-payment risk; the section still
  /// auto-hides when [bitcoinAddress] is empty. Does not affect Android.
  final bool iosBtcDonation;

  /// The navigation route to this screen (P14 DUP-3) — one definition for the
  /// donation banner and the settings entry point.
  static Route<void> route({
    TipJarService Function()? createTipJar,
    bool? tipJarMode,
    bool iosBtcDonation = const bool.fromEnvironment(
      'FEATURE_IOS_BTC_DONATION',
      defaultValue: true,
    ),
  }) => MaterialPageRoute<void>(
    builder: (_) => DonationScreen(
      createTipJar: createTipJar ?? _defaultTipJar,
      tipJarMode: tipJarMode,
      iosBtcDonation: iosBtcDonation,
    ),
  );

  Future<void> _openKofi(BuildContext context) async {
    final uri = Uri.tryParse(kofiUrl);
    if (uri == null) return;
    try {
      final ok = await openUrl(uri);
      if (ok) return;
    } catch (_) {
      // fall through to failure feedback
    }
    if (!context.mounted) return;
    context.showErrorSnack(context.l10n.donationErrorOpenKofi);
  }

  Future<void> _copyAddress(BuildContext context) async {
    await copyToClipboard(bitcoinAddress);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.donationBitcoinCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    final showTips = tipJarMode ?? tipJarAvailable;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: AppBackHeader(
        title: context.l10n.settingsSupportApp,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: showTips
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ..._headerChildren(context),
                const SizedBox(height: 18),
                TipJarBody(createService: createTipJar),
                // Bitcoin is display-only (no in-app payment), so it can also
                // appear on iOS after the tip consumables when enabled.
                if (iosBtcDonation && bitcoinAddress.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  _BitcoinSection(
                    key: const Key('donation-bitcoin-section'),
                    address: bitcoinAddress,
                    onCopy: () => _copyAddress(context),
                  ),
                ],
              ],
            )
          : _kofiBtcBody(context),
    );
  }

  /// Shared hero: favorite icon, headline, disclaimer, and the amber
  /// "donating unlocks nothing" note. Reused by both the tip-jar and the
  /// Ko-fi/BTC bodies (DRY).
  List<Widget> _headerChildren(BuildContext context) {
    final r = context.appColors;
    return [
      Icon(Icons.favorite, color: r.kofiRed, size: 34),
      const SizedBox(height: 8),
      Text(
        context.l10n.donationHeadline,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Figtree',
          fontWeight: FontWeight.w800,
          fontSize: 21,
          height: 1.25,
          color: r.ink,
        ),
      ),
      const SizedBox(height: 10),
      Text(
        context.l10n.donationDisclaimer,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: 'Figtree',
          fontSize: 13,
          height: 1.55,
          color: r.ink2,
        ),
      ),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: r.amberSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: r.amber),
        ),
        child: Text(
          context.l10n.donationOptionalNote,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontWeight: FontWeight.w500,
            fontSize: 12,
            height: 1.55,
            color: r.ink2,
          ),
        ),
      ),
    ];
  }

  Widget _kofiBtcBody(BuildContext context) {
    final r = context.appColors;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        ..._headerChildren(context),
        const SizedBox(height: 18),
        if (kofiUrl.isNotEmpty) ...[
          AppActionButton(
            key: const Key('donation-kofi-button'),
            label: context.l10n.donationKofiButton,
            icon: Icons.local_cafe_outlined,
            primary: true,
            fillColor: r.kofiRed,
            onPressed: () => _openKofi(context),
          ),
          const SizedBox(height: 11),
        ],
        if (bitcoinAddress.isNotEmpty)
          _BitcoinSection(
            key: const Key('donation-bitcoin-section'),
            address: bitcoinAddress,
            onCopy: () => _copyAddress(context),
          ),
      ],
    );
  }
}

class _BitcoinSection extends StatelessWidget {
  const _BitcoinSection({
    super.key,
    required this.address,
    required this.onCopy,
  });

  final String address;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final r = context.appColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: r.surface,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: r.line),
      ),
      child: Column(
        children: [
          Text(
            context.l10n.donationBitcoinHeading,
            style: TextStyle(
              fontFamily: 'Figtree',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: r.ink,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(
              data: 'bitcoin:$address',
              version: QrVersions.auto,
              size: 200,
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(
            address,
            textAlign: TextAlign.center,
            style: AppTypography.mono(size: 12, color: r.muted),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('donation-bitcoin-copy'),
            onPressed: onCopy,
            style: OutlinedButton.styleFrom(
              foregroundColor: r.greenDeep,
              side: BorderSide(color: r.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            icon: const Icon(Icons.copy),
            label: Text(context.l10n.donationCopyAddress),
          ),
        ],
      ),
    );
  }
}
