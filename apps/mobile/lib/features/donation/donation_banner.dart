import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/ream_colors.dart';
import 'donation_screen.dart';

/// A fixed, always-visible banner inviting the user to donate. Placed in a
/// Scaffold's bottomNavigationBar slot so it never scrolls over or overlaps
/// content. The whole banner is a single tap target that opens [DonationScreen].
class DonationBanner extends StatelessWidget {
  const DonationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final ream = context.ream;
    return Material(
      color: ream.amberSoft,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ream.amber, width: 1)),
          ),
          child: InkWell(
            key: const Key('donation-banner'),
            onTap: () => Navigator.of(context).push(DonationScreen.route()),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.favorite, color: ream.amber, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.l10n.donationBannerText,
                      style: TextStyle(color: ream.ink2),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: ream.amber),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
