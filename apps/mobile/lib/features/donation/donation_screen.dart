import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  Future<void> _openKofi() async {
    final uri = Uri.tryParse(kofiUrl);
    if (uri == null) return;
    // externalApplication keeps payment outside the app (App Store 3.1.1).
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: bitcoinAddress));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bitcoin address copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Support the app')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.favorite, color: Colors.amber.shade700, size: 48),
          const SizedBox(height: 16),
          Text(
            'Thank you for considering a donation!',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This is a voluntary donation only. You receive no features, '
            'benefits, or content in return — it simply helps support ongoing '
            'development.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          if (kofiUrl.isNotEmpty) ...[
            FilledButton.icon(
              key: const Key('donation-kofi-button'),
              onPressed: _openKofi,
              icon: const Icon(Icons.local_cafe_outlined),
              label: const Text('Donate via Ko-fi'),
            ),
            const SizedBox(height: 24),
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
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('Or donate with Bitcoin', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        SelectableText(
          address,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('donation-bitcoin-copy'),
          onPressed: onCopy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy address'),
        ),
        const SizedBox(height: 16),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: address,
            version: QrVersions.auto,
            size: 200,
          ),
        ),
      ],
    );
  }
}
