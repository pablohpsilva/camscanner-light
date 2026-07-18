import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../l10n/language_autonyms.dart';
import '../../l10n/locale_controller.dart';
import '../../l10n/locale_resolution.dart';
import '../../l10n/locale_store.dart';
import '../../theme/ream_colors.dart';
import '../../theme/widgets/ream_back_header.dart';
import '../../theme/widgets/ream_section_label.dart';
import '../../theme/widgets/ream_segmented.dart';
import '../../theme/theme_controller.dart';
import '../donation/donation_availability.dart';
import '../donation/donation_screen.dart';
import '../feedback/feedback_dependencies.dart';
import '../feedback/feedback_screen.dart';

/// App settings: theme selection (persisted via [ThemeController]), plus entry
/// points to feedback and support, and an About footer. Renders under the
/// active Ream theme (light or dark).
class SettingsScreen extends StatelessWidget {
  final ThemeController themeController;
  final LocaleController localeController;
  final FeedbackDependencies feedbackDependencies;
  final bool feedbackAvailable;

  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.localeController,
    this.feedbackDependencies = const FeedbackDependencies(),
    this.feedbackAvailable = true,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: context.l10n.settingsTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge([themeController, localeController]),
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            ReamSectionLabel(context.l10n.settingsSectionAppearance),
            const SizedBox(height: 10),
            ReamSegmented<ThemeMode>(
              key: const Key('settings-theme-mode'),
              expanded: true,
              value: themeController.mode,
              onChanged: themeController.setMode,
              segments: [
                ReamSegment(
                  value: ThemeMode.light,
                  label: context.l10n.settingsThemeLight,
                ),
                ReamSegment(
                  value: ThemeMode.dark,
                  label: context.l10n.settingsThemeDark,
                ),
                ReamSegment(
                  value: ThemeMode.system,
                  label: context.l10n.settingsThemeSystem,
                ),
              ],
            ),
            const SizedBox(height: 28),
            ReamSectionLabel(context.l10n.settingsSectionLanguage),
            const SizedBox(height: 10),
            _NavRow(
              key: const Key('settings-language'),
              icon: Icons.language,
              label: _currentLanguageLabel(context),
              onTap: () => _showLanguagePicker(context),
            ),
            const SizedBox(height: 28),
            ReamSectionLabel(context.l10n.settingsSectionFeedback),
            const SizedBox(height: 10),
            if (feedbackAvailable)
              _NavRow(
                key: const Key('settings-feedback'),
                icon: Icons.chat_bubble_outline,
                label: context.l10n.feedbackTitle,
                onTap: () => Navigator.of(
                  context,
                ).push(FeedbackScreen.route(feedbackDependencies)),
              ),
            if (donationEntryPointsAvailable)
              _NavRow(
                key: const Key('settings-support'),
                icon: Icons.favorite_outline,
                label: context.l10n.settingsSupportApp,
                onTap: () => Navigator.of(context).push(DonationScreen.route()),
              ),
            const SizedBox(height: 36),
            _About(key: const Key('settings-about')),
          ],
        ),
      ),
    );
  }

  String _currentLanguageLabel(BuildContext context) {
    final override = localeController.localeOverride;
    return override == null
        ? context.l10n.settingsLanguageSystem
        : kLanguageAutonyms[localeTag(override)]!;
  }

  Future<void> _showLanguagePicker(BuildContext context) async {
    final choice = await showDialog<_LanguageChoice>(
      context: context,
      builder: (context) {
        final current = localeController.localeOverride;
        Widget option({
          required String keySuffix,
          required String label,
          required Locale? locale,
          required bool selected,
        }) {
          return SimpleDialogOption(
            key: Key('language-option-$keySuffix'),
            onPressed: () => Navigator.pop(context, _LanguageChoice(locale)),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                if (selected) const Icon(Icons.check, size: 18),
              ],
            ),
          );
        }

        return SimpleDialog(
          title: Text(context.l10n.settingsSectionLanguage),
          children: [
            option(
              keySuffix: 'system',
              label: context.l10n.settingsLanguageSystem,
              locale: null,
              selected: current == null,
            ),
            for (final locale in kSupportedAppLocales)
              option(
                keySuffix: localeTag(locale),
                label: kLanguageAutonyms[localeTag(locale)]!,
                locale: locale,
                selected: current == locale,
              ),
          ],
        );
      },
    );
    if (choice != null) await localeController.setLocale(choice.locale);
  }
}

/// Wrapper so `null` (System default) is distinguishable from a dismissed dialog.
class _LanguageChoice {
  final Locale? locale;
  const _LanguageChoice(this.locale);
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
          context.l10n.appTitle,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: r.ink2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.l10n.settingsAboutTagline,
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
