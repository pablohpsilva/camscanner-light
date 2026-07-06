import 'package:flutter/material.dart';

import 'donation_screen.dart';

/// A fixed, always-visible banner inviting the user to donate. Placed in a
/// Scaffold's bottomNavigationBar slot so it never scrolls over or overlaps
/// content. The whole banner is a single tap target that opens [DonationScreen].
class DonationBanner extends StatelessWidget {
  const DonationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = Colors.amber.shade700;
    return Material(
      color: Colors.amber.shade50,
      child: SafeArea(
        top: false,
        child: InkWell(
          key: const Key('donation-banner'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DonationScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.local_cafe_outlined, color: amber),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Enjoying the app? Tap to support it ❤️'),
                ),
                Icon(Icons.chevron_right, color: amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
