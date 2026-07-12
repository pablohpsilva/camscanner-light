import 'package:flutter/material.dart';

import '../../theme/ream_colors.dart';
import '../../theme/widgets/ream_back_header.dart';
import '../../theme/widgets/ream_section_label.dart';
import '../../theme/widgets/ream_segmented.dart';
import '../../theme/theme_controller.dart';
import '../donation/donation_screen.dart';
import '../feedback/feedback_dependencies.dart';
import '../feedback/feedback_screen.dart';

/// App settings: theme selection (persisted via [ThemeController]), plus entry
/// points to feedback and support, and an About footer. Renders under the
/// active Ream theme (light or dark).
class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;
  final FeedbackDependencies feedbackDependencies;
  final bool feedbackAvailable;

  const SettingsScreen({
    super.key,
    required this.themeController,
    this.feedbackDependencies = const FeedbackDependencies(),
    this.feedbackAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: 'Settings',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const ReamSectionLabel('Appearance'),
            const SizedBox(height: 10),
            ReamSegmented<ThemeMode>(
              key: const Key('settings-theme-mode'),
              expanded: true,
              value: themeController.mode,
              onChanged: themeController.setMode,
              segments: const [
                ReamSegment(value: ThemeMode.light, label: 'Light'),
                ReamSegment(value: ThemeMode.dark, label: 'Dark'),
                ReamSegment(value: ThemeMode.system, label: 'System'),
              ],
            ),
            const SizedBox(height: 28),
            const ReamSectionLabel('Feedback & support'),
            const SizedBox(height: 10),
            if (feedbackAvailable)
              _NavRow(
                key: const Key('settings-feedback'),
                icon: Icons.chat_bubble_outline,
                label: 'Send feedback',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        FeedbackScreen(dependencies: feedbackDependencies),
                  ),
                ),
              ),
            _NavRow(
              key: const Key('settings-support'),
              icon: Icons.favorite_outline,
              label: 'Support the app',
              onTap: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DonationScreen())),
            ),
            const SizedBox(height: 36),
            _About(key: const Key('settings-about')),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _NavRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: r.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: r.line),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: r.ink2),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontFamily: 'Figtree',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: r.ink,
                    ),
                  ),
                ),
                Icon(Icons.chevron_right, size: 20, color: r.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _About extends StatelessWidget {
  const _About({super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Column(
      children: [
        Text(
          'CamScanner-light',
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: r.ink2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Your scans stay on your device — no account, no cloud.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 12.5,
            fontWeight: FontWeight.w400,
            color: r.muted,
          ),
        ),
      ],
    );
  }
}
