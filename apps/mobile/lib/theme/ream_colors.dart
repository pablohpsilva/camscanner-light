import 'package:flutter/material.dart';

/// Semantic color tokens for the Ream design system, carried on [ThemeData]
/// as a [ThemeExtension]. Values are the approved sRGB constants from
/// docs/design/ream/README.md (oklch converted to hex; ±1/channel tolerance).
@immutable
class ReamColors extends ThemeExtension<ReamColors> {
  final Color paper, surface, surface2, ink, ink2, muted, line, line2, appBg;
  final Color green, greenDeep, greenSoft, amber, amberSoft, blue, blueSoft;
  final Color kofiRed, deleteRed;

  const ReamColors({
    required this.paper,
    required this.surface,
    required this.surface2,
    required this.ink,
    required this.ink2,
    required this.muted,
    required this.line,
    required this.line2,
    required this.appBg,
    required this.green,
    required this.greenDeep,
    required this.greenSoft,
    required this.amber,
    required this.amberSoft,
    required this.blue,
    required this.blueSoft,
    required this.kofiRed,
    required this.deleteRed,
  });

  static const ReamColors light = ReamColors(
    paper: Color(0xFFF4F1EA),
    surface: Color(0xFFFFFDF8),
    surface2: Color(0xFFFAF7F0),
    ink: Color(0xFF33302A),
    ink2: Color(0xFF5C574D),
    muted: Color(0xFF928C80),
    line: Color(0xFFE6E1D6),
    line2: Color(0xFFEFEBE2),
    appBg: Color(0xFFE7E3D9),
    green: Color(0xFF4FA866),
    greenDeep: Color(0xFF2D7B44),
    greenSoft: Color(0xFFDEF1E1),
    amber: Color(0xFFCA932E),
    amberSoft: Color(0xFFFEECCD),
    blue: Color(0xFF4B99D7),
    blueSoft: Color(0xFFDFF1FF),
    kofiRed: Color(0xFFD5565D),
    deleteRed: Color(0xFFF47B74),
  );

  // Extrapolated from the 1b HUD screens (paper->#16130e ground, #211d16
  // surfaces, #322c22 lines, #f4f1ea ink; confidence hues unchanged). Real
  // values so the token is usable, but NOT verified live this phase.
  static const ReamColors dark = ReamColors(
    paper: Color(0xFF16130E),
    surface: Color(0xFF211D16),
    surface2: Color(0xFF1B1811),
    ink: Color(0xFFF4F1EA),
    ink2: Color(0xFFC9C2B4),
    muted: Color(0xFF8F887A),
    line: Color(0xFF322C22),
    line2: Color(0xFF2A251C),
    appBg: Color(0xFF0F0D09),
    green: Color(0xFF4FA866),
    greenDeep: Color(0xFF2D7B44),
    greenSoft: Color(0xFF1E3325),
    amber: Color(0xFFCA932E),
    amberSoft: Color(0xFF3A2F17),
    blue: Color(0xFF4B99D7),
    blueSoft: Color(0xFF17293A),
    kofiRed: Color(0xFFD5565D),
    deleteRed: Color(0xFFF47B74),
  );

  @override
  ReamColors copyWith({
    Color? paper,
    Color? surface,
    Color? surface2,
    Color? ink,
    Color? ink2,
    Color? muted,
    Color? line,
    Color? line2,
    Color? appBg,
    Color? green,
    Color? greenDeep,
    Color? greenSoft,
    Color? amber,
    Color? amberSoft,
    Color? blue,
    Color? blueSoft,
    Color? kofiRed,
    Color? deleteRed,
  }) {
    return ReamColors(
      paper: paper ?? this.paper,
      surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2,
      ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      line2: line2 ?? this.line2,
      appBg: appBg ?? this.appBg,
      green: green ?? this.green,
      greenDeep: greenDeep ?? this.greenDeep,
      greenSoft: greenSoft ?? this.greenSoft,
      amber: amber ?? this.amber,
      amberSoft: amberSoft ?? this.amberSoft,
      blue: blue ?? this.blue,
      blueSoft: blueSoft ?? this.blueSoft,
      kofiRed: kofiRed ?? this.kofiRed,
      deleteRed: deleteRed ?? this.deleteRed,
    );
  }

  @override
  ReamColors lerp(ThemeExtension<ReamColors>? other, double t) {
    if (other is! ReamColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ReamColors(
      paper: l(paper, other.paper),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2),
      muted: l(muted, other.muted),
      line: l(line, other.line),
      line2: l(line2, other.line2),
      appBg: l(appBg, other.appBg),
      green: l(green, other.green),
      greenDeep: l(greenDeep, other.greenDeep),
      greenSoft: l(greenSoft, other.greenSoft),
      amber: l(amber, other.amber),
      amberSoft: l(amberSoft, other.amberSoft),
      blue: l(blue, other.blue),
      blueSoft: l(blueSoft, other.blueSoft),
      kofiRed: l(kofiRed, other.kofiRed),
      deleteRed: l(deleteRed, other.deleteRed),
    );
  }
}

/// Theme-INDEPENDENT overlay constants (P15). A scrim dims content the same
/// whether the page is warm-paper or dark, and a card shadow is alpha-black in
/// both — so these are plain named consts, not theme-varying tokens. They live
/// here so the ONLY `Color(0x…)` literals in the app are in this file.
const Color kReamScrimStrong = Color(0x99000000); // ~60% black — modal/busy dim
const Color kReamScrimMedium = Color(0x66000000); // ~40% black — lighter dim
const Color kReamCardShadow = Color(0x14000000); // ~8% black — subtle card shadow

/// The contrasting "ink" to place on a [fill] of arbitrary brightness (P15):
/// white on dark fills, warm near-black on bright fills. Theme-independent — it
/// depends only on the fill's luminance. Dedups the identical brightness ternary
/// that lived in `ream_action_button` and `feedback_screen`.
Color reamInkOnFill(Color fill) =>
    ThemeData.estimateBrightnessForColor(fill) == Brightness.dark
    ? Colors.white
    : const Color(0xFF201C16);

/// Terse access: `context.ream.green`.
///
/// Falls back to [ReamColors.light] when no [ReamColors] extension is
/// registered on the theme. Production always registers it (light or dark) via
/// `ReamTheme` in `main.dart`, so the fallback only applies in widget tests that
/// pump a component under a bare `MaterialApp` — those render with the light
/// palette instead of crashing, which keeps the token usable everywhere.
extension ReamColorsX on BuildContext {
  ReamColors get ream =>
      Theme.of(this).extension<ReamColors>() ?? ReamColors.light;
}
