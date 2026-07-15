import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../../theme/ream_colors.dart';
import '../../theme/ream_typography.dart';
import '../../theme/widgets/ream_action_button.dart';
import '../../theme/widgets/ream_back_header.dart';
import 'donation_config.dart';

/// Full-screen donation page. Ko-fi opens in the external browser (store-safe:
/// no in-app payment collection); Bitcoin is display-only (QR + copyable
/// address). Sections hide when their config value is empty. A prominent
/// disclaimer states donations grant no benefits.
class DonationScreen extends StatelessWidget {
  const DonationScreen({
    super.key,
    this.kofiUrl = DonationConfig.kofiUrl,
    this.bitcoinAddress = DonationConfig.bitcoinAddress,
  });

  final String kofiUrl;
  final String bitcoinAddress;

  Future<void> _openKofi(BuildContext context) async {
    final uri = Uri.tryParse(kofiUrl);
    if (uri == null) return;
    try {
      // externalApplication keeps payment outside the app (App Store 3.1.1).
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (ok) return;
    } catch (_) {
      // fall through to failure feedback
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.donationErrorOpenKofi)));
  }

  Future<void> _copyAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: bitcoinAddress));
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.donationBitcoinCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: context.l10n.settingsSupportApp,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
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
          const SizedBox(height: 18),
          if (kofiUrl.isNotEmpty) ...[
            ReamActionButton(
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
      ),
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
    final r = context.ream;
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
            style: ReamTypography.mono(size: 12, color: r.muted),
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
