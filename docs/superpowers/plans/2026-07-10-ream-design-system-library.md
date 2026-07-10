# Ream Design System + Library — Implementation Plan (Phase 1)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the themable Ream design system (`lib/theme/`) and re-skin the
Library (Home) screen — inline search, new grid view, bottom action row — live on
the Ream light theme, green on host + real Android + real iOS.

**Architecture:** A `ReamColors` `ThemeExtension` holds every semantic token; a
`ReamTheme` builds light/dark `ThemeData` and registers it on `MaterialApp`.
Small, independently-tested reusable widgets (`lib/theme/widgets/`) compose the
restructured `HomeScreen`. Existing `HomeScreen` state/data-flow is preserved;
only presentation + the search interaction change.

**Tech Stack:** Flutter (Material 3), `ThemeExtension`, bundled OFL fonts
(Figtree variable + IBM Plex Mono static), `bdd_widget_test`, `drift`.

## Global Constraints

Copied verbatim from `docs/design/ream/README.md` and `CLAUDE.md`. **Every task
implicitly includes this section.**

- **Run all Flutter commands from `apps/mobile/`** (not repo root).
- **Direction 1a warm & clean (light).** Dark theme is a stub this phase (real
  values, but not verified live). Do not implement capture/ID-scan screens.
- **No rename.** Keep app name/ids/copy; introduce no literal "Ream" in UI copy.
- **Colors:** use only the approved constants in the token table
  (`docs/design/ream/README.md`). Flutter `Color` cannot parse oklch — the hex
  values in that table are authoritative. ±1/channel tolerance.
- **Type:** Figtree (family `Figtree`) for UI; IBM Plex Mono (family
  `IBMPlexMono`) for technical readouts only.
- **Definition of done (per task):** (1) failing host test written first; (2)
  minimal code to green; (3) `flutter analyze` zero warnings; (4)
  `dart format lib test`; (5) commit. User-facing behavior also needs a BDD
  `.feature` (Wave 3). Native-dependent behavior needs a real Android **and** real
  iOS device run, or an explicitly named gap — never silent.
- **Verify, then claim.** Paste the exact command + green output before checking a
  step done. No "should work".

---

## Parallelization map

Tasks are grouped into **waves**. Within a wave, tasks whose file sets are
**disjoint** run in parallel subagents. Across waves, later waves depend on
earlier ones. **Never run two tasks that write the same file concurrently.**

| Wave | Tasks | Parallel? | Shared/owned files |
|------|-------|-----------|--------------------|
| **0 Foundation** | 1 Fonts · 2 ReamColors · 3 Typography · 4 Theme+wire · 5 Test helper | **Serial** (small; touch `pubspec.yaml`, `main.dart`, new `lib/theme/*` root). Order: 1→2→3→4; 5 any time after 2. | `pubspec.yaml`, `lib/main.dart`, `lib/theme/ream_colors.dart`, `ream_typography.dart`, `ream_theme.dart`, `test/support/ream_pump.dart` |
| **1 Widgets** | 6 ConfidenceChip · 7 ReamSearchField · 8 ReamSegmented · 9 ReamActionButton · 10 DocumentGridCard · 11 DocumentsGridView · 12 SortPill · 13 DonationBanner restyle | **Parallel** (each creates its own new file + test; 11 depends on 10 so run 11 after 10). 13 modifies an existing file+test, disjoint from others. | one new `lib/theme/widgets/<x>.dart` + `test/features/theme/<x>_test.dart` each; 13 → `lib/features/donation/donation_banner.dart` |
| **2 Integration** | 14 HomeScreen restructure + host-test updates · 15 DocumentsListView restyle | **Serial, single owner** — both waves touch `home_screen.dart`/list view + their tests. Do 15 then 14, one agent. | `lib/features/library/home_screen.dart`, `widgets/documents_list_view.dart`, all `test/features/library/home_*_test.dart` |
| **3 Verify** | 16 BDD features + steps + build_runner · 17 Host gate (analyze/format/full suite) · 18 Device run (Android+iOS) | 16→17 serial; 18 gated on real devices. | `integration_test/*.feature`, `test/step/*`, generated `*_test.dart` |

**Fan-out:** Wave 1 is the big parallel opportunity — up to **8 subagents at once**
(7 after folding 11-behind-10). Dispatch them together via
`superpowers:dispatching-parallel-agents`.

---

## Strict subagent contract

Every subagent dispatched for a task MUST be given this contract and MUST satisfy
it before reporting done. A task is **not done** until all boxes are literally
true and evidenced.

1. **Read first:** `docs/design/ream/README.md` (tokens, type, DoD) and this
   plan's Global Constraints + your task block. Do not invent colors, names, or
   file paths — use exactly what the task's **Interfaces** block specifies.
2. **Own only your files.** Create/modify only the paths in your task's **Files**
   block. If you believe you must touch another file, STOP and report — do not
   edit it (another agent may own it concurrently).
3. **TDD order is mandatory.** Write the test, run it, and **paste the FAIL
   output** (a test that passes before implementation is a broken test — fix it).
   Then implement, run, and **paste the PASS output**.
4. **Real tests only.** No `skip:`, no commented assertions, no `expect(true,
   isTrue)` filler, no deleting/loosening an assertion to get green. Test observable
   behavior (rendered text/colors/keys/callbacks), not implementation details.
5. **Gate before commit, every task:**
   - `flutter test <your test file(s)>` → paste PASS.
   - `flutter analyze` → must print **"No issues found!"**. Paste it.
   - `dart format lib test` → run it.
6. **Commit** only your task's files (scoped `git add <paths>`, never `-A` — the
   tree carries an unrelated WIP pile). Message: `feat(theme|library): <task>`.
   End every commit message with the two trailer lines in `CLAUDE.md`.
7. **Report** back: the exact commands you ran, the pasted FAIL→PASS + analyze
   output, the commit SHA, and any named gap (e.g. "device lane not run — no iOS
   device attached"). If you could not satisfy a box, say which and why — never
   claim done with an open gap.
8. **Host-test hazards** (this repo): OpenCV/`libdartcv` does not load under plain
   `flutter test` — that's environmental, not your bug. `Image.file` on a real
   path hangs widget tests — use a non-loadable path in tests (see
   `DocumentThumbnail`). `pumpAndSettle` hangs on perpetual spinners.

---

## Task 1: Bundle Figtree + IBM Plex Mono fonts

**Files:**
- Create: `apps/mobile/fonts/Figtree[wght].ttf`, `apps/mobile/fonts/IBMPlexMono-Regular.ttf`, `IBMPlexMono-Medium.ttf`, `IBMPlexMono-SemiBold.ttf`
- Modify: `apps/mobile/pubspec.yaml` (add `fonts:` block)
- Create: `apps/mobile/fonts/OFL.txt` (license notice)

**Interfaces:**
- Produces: font families `Figtree` (variable, weights 400–800) and `IBMPlexMono`
  (400/500/600), usable via `TextStyle(fontFamily: ...)`.

- [ ] **Step 1: Download the OFL fonts (verify each is real, not an error page)**

```bash
cd apps/mobile && mkdir -p fonts
curl -fL -o "fonts/Figtree[wght].ttf"      "https://github.com/google/fonts/raw/main/ofl/figtree/Figtree%5Bwght%5D.ttf"
curl -fL -o "fonts/IBMPlexMono-Regular.ttf"  "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Regular.ttf"
curl -fL -o "fonts/IBMPlexMono-Medium.ttf"   "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-Medium.ttf"
curl -fL -o "fonts/IBMPlexMono-SemiBold.ttf" "https://github.com/google/fonts/raw/main/ofl/ibmplexmono/IBMPlexMono-SemiBold.ttf"
curl -fL -o "fonts/OFL.txt"                  "https://github.com/google/fonts/raw/main/ofl/figtree/OFL.txt"
# Verify: each ttf must start with the TrueType magic and be > 40KB
for f in fonts/*.ttf; do printf '%s ' "$f"; head -c4 "$f" | xxd -p; wc -c < "$f"; done
```

Expected: each `.ttf` prints `00010000` (or `4f54544f`) and a byte count > 40000.
If any is a few-hundred-byte HTML error page, the URL is wrong — STOP and report.

- [ ] **Step 2: Declare the fonts in `pubspec.yaml`**

Under the existing `flutter:` section, after the `assets:` block, add:

```yaml
  fonts:
    - family: Figtree
      fonts:
        - asset: fonts/Figtree[wght].ttf
    - family: IBMPlexMono
      fonts:
        - asset: fonts/IBMPlexMono-Regular.ttf
        - asset: fonts/IBMPlexMono-Medium.ttf
          weight: 500
        - asset: fonts/IBMPlexMono-SemiBold.ttf
          weight: 600
```

- [ ] **Step 3: Resolve + analyze**

```bash
cd apps/mobile && flutter pub get && flutter analyze
```
Expected: `pub get` succeeds; `flutter analyze` → "No issues found!".

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/fonts apps/mobile/pubspec.yaml
git commit -m "feat(theme): bundle Figtree + IBM Plex Mono OFL fonts"   # + CLAUDE.md trailers
```

---

## Task 2: `ReamColors` ThemeExtension + `context.ream`

**Files:**
- Create: `apps/mobile/lib/theme/ream_colors.dart`
- Test: `apps/mobile/test/features/theme/ream_colors_test.dart`

**Interfaces:**
- Produces: `class ReamColors extends ThemeExtension<ReamColors>` with `Color`
  fields `paper, surface, surface2, ink, ink2, muted, line, line2, appBg, green,
  greenDeep, greenSoft, amber, amberSoft, blue, blueSoft, kofiRed, deleteRed`;
  `static const ReamColors.light`, `static const ReamColors.dark`; `copyWith`,
  `lerp`. Plus `extension ReamColorsX on BuildContext { ReamColors get ream; }`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';

void main() {
  test('light tokens match the approved palette', () {
    const c = ReamColors.light;
    expect(c.paper, const Color(0xFFF4F1EA));
    expect(c.green, const Color(0xFF4FA866));
    expect(c.greenDeep, const Color(0xFF2D7B44));
    expect(c.amberSoft, const Color(0xFFFEECCD));
  });

  test('lerp interpolates halfway', () {
    final mid = ReamColors.light.lerp(ReamColors.dark, 0.5);
    expect(mid, isA<ReamColors>());
  });

  testWidgets('context.ream resolves from a themed context', (tester) async {
    late ReamColors seen;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: const [ReamColors.light]),
      home: Builder(builder: (context) {
        seen = context.ream;
        return const SizedBox();
      }),
    ));
    expect(seen.paper, const Color(0xFFF4F1EA));
  });
}
```

- [ ] **Step 2: Run — expect FAIL** (`ream_colors.dart` does not exist)

```bash
cd apps/mobile && flutter test test/features/theme/ream_colors_test.dart
```

- [ ] **Step 3: Implement**

```dart
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
    required this.paper, required this.surface, required this.surface2,
    required this.ink, required this.ink2, required this.muted,
    required this.line, required this.line2, required this.appBg,
    required this.green, required this.greenDeep, required this.greenSoft,
    required this.amber, required this.amberSoft, required this.blue,
    required this.blueSoft, required this.kofiRed, required this.deleteRed,
  });

  static const ReamColors light = ReamColors(
    paper: Color(0xFFF4F1EA), surface: Color(0xFFFFFDF8),
    surface2: Color(0xFFFAF7F0), ink: Color(0xFF33302A),
    ink2: Color(0xFF5C574D), muted: Color(0xFF928C80),
    line: Color(0xFFE6E1D6), line2: Color(0xFFEFEBE2), appBg: Color(0xFFE7E3D9),
    green: Color(0xFF4FA866), greenDeep: Color(0xFF2D7B44),
    greenSoft: Color(0xFFDEF1E1), amber: Color(0xFFCA932E),
    amberSoft: Color(0xFFFEECCD), blue: Color(0xFF4B99D7),
    blueSoft: Color(0xFFDFF1FF), kofiRed: Color(0xFFD5565D),
    deleteRed: Color(0xFFF47B74),
  );

  // Extrapolated from the 1b HUD screens (paper->#16130e ground, #211d16
  // surfaces, #322c22 lines, #f4f1ea ink; confidence hues unchanged). Real
  // values so the token is usable, but NOT verified live this phase.
  static const ReamColors dark = ReamColors(
    paper: Color(0xFF16130E), surface: Color(0xFF211D16),
    surface2: Color(0xFF1B1811), ink: Color(0xFFF4F1EA),
    ink2: Color(0xFFC9C2B4), muted: Color(0xFF8F887A),
    line: Color(0xFF322C22), line2: Color(0xFF2A251C), appBg: Color(0xFF0F0D09),
    green: Color(0xFF4FA866), greenDeep: Color(0xFF2D7B44),
    greenSoft: Color(0xFF1E3325), amber: Color(0xFFCA932E),
    amberSoft: Color(0xFF3A2F17), blue: Color(0xFF4B99D7),
    blueSoft: Color(0xFF17293A), kofiRed: Color(0xFFD5565D),
    deleteRed: Color(0xFFF47B74),
  );

  @override
  ReamColors copyWith({
    Color? paper, Color? surface, Color? surface2, Color? ink, Color? ink2,
    Color? muted, Color? line, Color? line2, Color? appBg, Color? green,
    Color? greenDeep, Color? greenSoft, Color? amber, Color? amberSoft,
    Color? blue, Color? blueSoft, Color? kofiRed, Color? deleteRed,
  }) {
    return ReamColors(
      paper: paper ?? this.paper, surface: surface ?? this.surface,
      surface2: surface2 ?? this.surface2, ink: ink ?? this.ink,
      ink2: ink2 ?? this.ink2, muted: muted ?? this.muted,
      line: line ?? this.line, line2: line2 ?? this.line2,
      appBg: appBg ?? this.appBg, green: green ?? this.green,
      greenDeep: greenDeep ?? this.greenDeep, greenSoft: greenSoft ?? this.greenSoft,
      amber: amber ?? this.amber, amberSoft: amberSoft ?? this.amberSoft,
      blue: blue ?? this.blue, blueSoft: blueSoft ?? this.blueSoft,
      kofiRed: kofiRed ?? this.kofiRed, deleteRed: deleteRed ?? this.deleteRed,
    );
  }

  @override
  ReamColors lerp(ThemeExtension<ReamColors>? other, double t) {
    if (other is! ReamColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return ReamColors(
      paper: l(paper, other.paper), surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2), ink: l(ink, other.ink),
      ink2: l(ink2, other.ink2), muted: l(muted, other.muted),
      line: l(line, other.line), line2: l(line2, other.line2),
      appBg: l(appBg, other.appBg), green: l(green, other.green),
      greenDeep: l(greenDeep, other.greenDeep), greenSoft: l(greenSoft, other.greenSoft),
      amber: l(amber, other.amber), amberSoft: l(amberSoft, other.amberSoft),
      blue: l(blue, other.blue), blueSoft: l(blueSoft, other.blueSoft),
      kofiRed: l(kofiRed, other.kofiRed), deleteRed: l(deleteRed, other.deleteRed),
    );
  }
}

/// Terse access: `context.ream.green`.
extension ReamColorsX on BuildContext {
  ReamColors get ream => Theme.of(this).extension<ReamColors>()!;
}
```

- [ ] **Step 4: Run — expect PASS.** `flutter test test/features/theme/ream_colors_test.dart`
- [ ] **Step 5: analyze + format + commit** (`feat(theme): ReamColors ThemeExtension + context.ream`)

---

## Task 3: `ReamTypography`

**Files:**
- Create: `apps/mobile/lib/theme/ream_typography.dart`
- Test: `apps/mobile/test/features/theme/ream_typography_test.dart`

**Interfaces:**
- Produces: `class ReamTypography` with `static TextTheme textTheme(Color ink)`
  (all styles `fontFamily: 'Figtree'`; `displayLarge`/`headline*` weight 800) and
  `static TextStyle mono({double size = 12, FontWeight weight = FontWeight.w500,
  Color? color, double letterSpacing = 0})` (`fontFamily: 'IBMPlexMono'`).

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_typography.dart';

void main() {
  test('UI text theme uses Figtree', () {
    final t = ReamTypography.textTheme(const Color(0xFF33302A));
    expect(t.titleLarge!.fontFamily, 'Figtree');
    expect(t.bodyMedium!.color, const Color(0xFF33302A));
  });
  test('mono uses IBM Plex Mono', () {
    final s = ReamTypography.mono(size: 11, weight: FontWeight.w600);
    expect(s.fontFamily, 'IBMPlexMono');
    expect(s.fontWeight, FontWeight.w600);
    expect(s.fontSize, 11);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';

/// Ream typography: Figtree for UI, IBM Plex Mono for technical readouts.
class ReamTypography {
  static const _ui = 'Figtree';
  static const _mono = 'IBMPlexMono';

  static TextTheme textTheme(Color ink) {
    TextStyle f(double size, FontWeight w, {double spacing = 0}) => TextStyle(
          fontFamily: _ui, fontSize: size, fontWeight: w,
          color: ink, letterSpacing: spacing, height: 1.2,
        );
    return TextTheme(
      displayLarge: f(28, FontWeight.w800, spacing: -0.5),
      headlineMedium: f(24, FontWeight.w800, spacing: -0.4),
      titleLarge: f(18, FontWeight.w700),
      titleMedium: f(15, FontWeight.w600),
      bodyLarge: f(14.5, FontWeight.w500),
      bodyMedium: f(13, FontWeight.w400),
      labelLarge: f(13.5, FontWeight.w600),
      labelMedium: f(12, FontWeight.w600),
    );
  }

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w500,
    Color? color,
    double letterSpacing = 0,
  }) => TextStyle(
        fontFamily: _mono, fontSize: size, fontWeight: weight,
        color: color, letterSpacing: letterSpacing,
      );
}
```

- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: analyze + format + commit** (`feat(theme): ReamTypography (Figtree + IBM Plex Mono)`)

---

## Task 4: `ReamTheme` (light/dark) + wire `MaterialApp`

**Files:**
- Create: `apps/mobile/lib/theme/ream_theme.dart`
- Test: `apps/mobile/test/features/theme/ream_theme_test.dart`
- Modify: `apps/mobile/lib/main.dart` (use the theme)

**Interfaces:**
- Consumes: `ReamColors` (Task 2), `ReamTypography` (Task 3).
- Produces: `class ReamTheme` with `static ThemeData light()` and
  `static ThemeData dark()`. `light()` carries `ReamColors.light` in
  `extensions`, `scaffoldBackgroundColor == ReamColors.light.paper`, a
  green-seeded `ColorScheme`, and the Figtree `textTheme`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';

void main() {
  test('light theme carries ReamColors + paper scaffold + Figtree', () {
    final t = ReamTheme.light();
    expect(t.extension<ReamColors>(), ReamColors.light);
    expect(t.scaffoldBackgroundColor, ReamColors.light.paper);
    expect(t.textTheme.titleLarge!.fontFamily, 'Figtree');
    expect(t.brightness, Brightness.light);
  });
  test('dark theme carries dark tokens', () {
    expect(ReamTheme.dark().extension<ReamColors>(), ReamColors.dark);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement `ream_theme.dart`**

```dart
import 'package:flutter/material.dart';
import 'ream_colors.dart';
import 'ream_typography.dart';

/// Builds the Ream [ThemeData] for light and dark, mapping [ReamColors] onto a
/// Material [ColorScheme] so stock widgets inherit sensible colors.
class ReamTheme {
  static ThemeData light() => _build(ReamColors.light, Brightness.light);
  static ThemeData dark() => _build(ReamColors.dark, Brightness.dark);

  static ThemeData _build(ReamColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.greenDeep,
      brightness: brightness,
    ).copyWith(
      surface: c.surface,
      primary: c.greenDeep,
      error: c.deleteRed,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.paper,
      textTheme: ReamTypography.textTheme(c.ink),
      extensions: [c],
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**
- [ ] **Step 5: Wire `main.dart`** — replace the `theme:` line:

```dart
// import 'theme/ream_theme.dart';
return MaterialApp(
  title: 'CamScanner-light',
  debugShowCheckedModeBanner: false,
  theme: ReamTheme.light(),
  darkTheme: ReamTheme.dark(),
  themeMode: ThemeMode.light, // light-first; dark verified in the final phase
  home: HomeScreen(
    dependencies: scanDependencies,
    libraryDependencies: libraryDependencies,
    feedbackDependencies: feedbackDependencies,
  ),
);
```

- [ ] **Step 6: Full host suite still green** (theme swap must not break existing tests):

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all pass; "No issues found!". If a pre-existing test asserted the old
indigo scheme, update that assertion (name it in the commit).

- [ ] **Step 7: format + commit** (`feat(theme): ReamTheme light/dark + wire MaterialApp`)

---

## Task 5: `pumpReam` test helper

**Files:**
- Create: `apps/mobile/test/support/ream_pump.dart`

**Interfaces:**
- Produces: `Future<void> pumpReam(WidgetTester tester, Widget child, {ThemeData? theme})`
  — pumps `child` inside a `MaterialApp` themed with `ReamTheme.light()` and a
  `Scaffold` body, so widgets that read `context.ream` resolve. Wave 1 widget
  tests import this.

- [ ] **Step 1: Implement (no separate test — exercised by Wave 1 tests)**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';

/// Pumps [child] inside a Ream-themed MaterialApp+Scaffold for widget tests.
Future<void> pumpReam(WidgetTester tester, Widget child, {ThemeData? theme}) {
  return tester.pumpWidget(MaterialApp(
    theme: theme ?? ReamTheme.light(),
    home: Scaffold(body: child),
  ));
}
```

- [ ] **Step 2: analyze + commit** (`test(theme): pumpReam widget-test helper`)

---

## Task 6: `ConfidenceChip`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/theme/widgets/confidence_chip.dart`
- Test: `apps/mobile/test/features/theme/confidence_chip_test.dart`

**Interfaces:**
- Consumes: `context.ream`, `pumpReam`.
- Produces: `enum ConfidenceLevel { high, verify, info }` and
  `class ConfidenceChip extends StatelessWidget` with
  `ConfidenceChip({required ConfidenceLevel level, required String label, Key? key})`.
  `high→green`, `verify→amber`, `info→blue`. Renders a rounded pill with a
  leading dot + label; the label text is findable.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/widgets/confidence_chip.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('high confidence renders label + green dot', (tester) async {
    await pumpReam(tester, const ConfidenceChip(
      level: ConfidenceLevel.high, label: 'High confidence'));
    expect(find.text('High confidence'), findsOneWidget);
    final dot = tester.widget<DecoratedBox>(find.byKey(
      const Key('confidence-dot')));
    expect((dot.decoration as BoxDecoration).color, ReamColors.light.green);
  });

  testWidgets('verify level uses amber', (tester) async {
    await pumpReam(tester, const ConfidenceChip(
      level: ConfidenceLevel.verify, label: 'Please verify'));
    final dot = tester.widget<DecoratedBox>(find.byKey(
      const Key('confidence-dot')));
    expect((dot.decoration as BoxDecoration).color, ReamColors.light.amber);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';
import '../ream_typography.dart';

enum ConfidenceLevel { high, verify, info }

/// A rounded status pill using the confidence trio: green (high), amber
/// (verify), blue (info). A leading dot + label.
class ConfidenceChip extends StatelessWidget {
  final ConfidenceLevel level;
  final String label;
  const ConfidenceChip({super.key, required this.level, required this.label});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final (dot, fg, bg) = switch (level) {
      ConfidenceLevel.high => (r.green, r.greenDeep, r.greenSoft),
      ConfidenceLevel.verify => (r.amber, r.ink2, r.amberSoft),
      ConfidenceLevel.info => (r.blue, r.ink2, r.blueSoft),
    };
    return Container(
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(20),
        border: Border.all(color: dot),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        DecoratedBox(
          key: const Key('confidence-dot'),
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          child: const SizedBox(width: 7, height: 7),
        ),
        const SizedBox(width: 7),
        Text(label, style: ReamTypography.mono(
          size: 12, weight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(theme): ConfidenceChip (green/amber/blue)`).

---

## Task 7: `ReamSearchField`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/theme/widgets/ream_search_field.dart`
- Test: `apps/mobile/test/features/theme/ream_search_field_test.dart`

**Interfaces:**
- Produces: `class ReamSearchField extends StatelessWidget` with
  `ReamSearchField({required TextEditingController controller, required
  ValueChanged<String> onChanged, String hintText = 'Search titles & text inside
  pages', VoidCallback? onClear, Key? key})`. Contains a `TextField` (leading
  search icon; trailing clear button shown when `controller.text` non-empty)
  styled with surface bg + `line` border. Default field key `documents-search-field`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/widgets/ream_search_field.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('typing calls onChanged; hint shown', (tester) async {
    final controller = TextEditingController();
    String? last;
    await pumpReam(tester, ReamSearchField(
      controller: controller, onChanged: (v) => last = v));
    expect(find.text('Search titles & text inside pages'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('documents-search-field')), 'lease');
    expect(last, 'lease');
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';

/// Inline, always-visible search field in the Ream header style.
class ReamSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;
  final VoidCallback? onClear;
  const ReamSearchField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.hintText = 'Search titles & text inside pages',
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: r.surface, borderRadius: BorderRadius.circular(13),
        border: Border.all(color: r.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13),
      child: Row(children: [
        Icon(Icons.search, size: 18, color: r.muted),
        const SizedBox(width: 9),
        Expanded(
          child: TextField(
            key: const Key('documents-search-field'),
            controller: controller,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: r.ink, fontSize: 14),
            decoration: InputDecoration(
              isCollapsed: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 13),
              hintText: hintText,
              hintStyle: TextStyle(color: r.muted, fontSize: 13.5),
              border: InputBorder.none,
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          GestureDetector(
            key: const Key('documents-search-clear'),
            onTap: () { controller.clear(); onChanged(''); onClear?.call(); },
            child: Icon(Icons.close, size: 16, color: r.muted),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(theme): ReamSearchField inline search`).

---

## Task 8: `ReamSegmented`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/theme/widgets/ream_segmented.dart`
- Test: `apps/mobile/test/features/theme/ream_segmented_test.dart`

**Interfaces:**
- Produces: `class ReamSegment<T> { final T value; final String label; final
  IconData? icon; const ReamSegment({required this.value, required this.label,
  this.icon}); }` and `class ReamSegmented<T> extends StatelessWidget` with
  `ReamSegmented({required List<ReamSegment<T>> segments, required T value,
  required ValueChanged<T> onChanged, Key? key})`. Active segment: `ink` bg +
  `surface` text; inactive: `muted` text. Each segment tappable; keys
  `segment-<value>`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/widgets/ream_segmented.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('tapping a segment fires onChanged with its value', (tester) async {
    String value = 'list';
    await pumpReam(tester, StatefulBuilder(builder: (_, setState) {
      return ReamSegmented<String>(
        value: value,
        segments: const [
          ReamSegment(value: 'list', label: 'List'),
          ReamSegment(value: 'grid', label: 'Grid'),
        ],
        onChanged: (v) => setState(() => value = v),
      );
    }));
    await tester.tap(find.byKey(const Key('segment-grid')));
    await tester.pump();
    expect(value, 'grid');
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';

class ReamSegment<T> {
  final T value;
  final String label;
  final IconData? icon;
  const ReamSegment({required this.value, required this.label, this.icon});
}

/// A compact segmented toggle in the Ream style (e.g. List / Grid).
class ReamSegmented<T> extends StatelessWidget {
  final List<ReamSegment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  const ReamSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Container(
      decoration: BoxDecoration(
        color: r.surface, borderRadius: BorderRadius.circular(9),
        border: Border.all(color: r.line),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final s in segments)
          GestureDetector(
            key: Key('segment-${s.value}'),
            onTap: () => onChanged(s.value),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: s.value == value ? r.ink : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(s.label, style: TextStyle(
                fontFamily: 'Figtree', fontSize: 11.5, fontWeight: FontWeight.w600,
                color: s.value == value ? r.surface : r.muted,
              )),
            ),
          ),
      ]),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(theme): ReamSegmented toggle`).

---

## Task 9: `ReamActionButton`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/theme/widgets/ream_action_button.dart`
- Test: `apps/mobile/test/features/theme/ream_action_button_test.dart`

**Interfaces:**
- Produces: `class ReamActionButton extends StatelessWidget` with
  `ReamActionButton({required String label, IconData? icon, VoidCallback?
  onPressed, bool primary = false, Key? key})`. `primary` → `greenDeep` fill,
  white label, horizontal icon+label. Secondary → `surface` fill, `line` border,
  `ink2` label, vertical icon-over-label. Disabled when `onPressed == null`.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/widgets/ream_action_button.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('tapping fires onPressed; label shown', (tester) async {
    var taps = 0;
    await pumpReam(tester, ReamActionButton(
      key: const Key('act-scan'), label: 'Scan', icon: Icons.add,
      primary: true, onPressed: () => taps++));
    expect(find.text('Scan'), findsOneWidget);
    await tester.tap(find.byKey(const Key('act-scan')));
    expect(taps, 1);
  });

  testWidgets('null onPressed disables the button', (tester) async {
    await pumpReam(tester, const ReamActionButton(
      key: Key('act-x'), label: 'X', onPressed: null));
    await tester.tap(find.byKey(const Key('act-x')));
    // no throw, no callback — nothing to assert beyond not crashing
    expect(find.text('X'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement**

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';

/// A Ream action button. [primary] is the filled green CTA (icon beside label);
/// secondary is an outlined surface tile (icon above label).
class ReamActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool primary;
  const ReamActionButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final enabled = onPressed != null;
    final child = primary
        ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 8)],
            Text(label, style: const TextStyle(
              fontFamily: 'Figtree', fontSize: 15, fontWeight: FontWeight.w700,
              color: Colors.white)),
          ])
        : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (icon != null) ...[Icon(icon, size: 18, color: r.ink2),
              const SizedBox(height: 3)],
            Text(label, style: TextStyle(
              fontFamily: 'Figtree', fontSize: 11, fontWeight: FontWeight.w600,
              color: r.ink2)),
          ]);
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: primary ? r.greenDeep : r.surface,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            height: primary ? 52 : 52,
            decoration: primary
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: r.line)),
            alignment: Alignment.center,
            child: child,
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(theme): ReamActionButton`).

---

## Task 10: `DocumentGridCard`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/document_grid_card.dart`
- Test: `apps/mobile/test/features/library/document_grid_card_test.dart`

**Interfaces:**
- Consumes: `DocumentSummary`, `DocumentThumbnail`, `ReamTypography`, `context.ream`.
- Produces: `class DocumentGridCard extends StatelessWidget` with
  `DocumentGridCard({required DocumentSummary summary, VoidCallback? onTap,
  VoidCallback? onLongPress, bool selected = false, bool selectionMode = false,
  Key? key})`. Renders a paper card: thumbnail area (`aspect-ratio .77`), title
  (`titleMedium`), and a mono meta line `Np · <date>`. Card key
  `document-card-<id>`; selected shows a check.

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/document_grid_card.dart';
import '../../support/ream_pump.dart';

DocumentSummary _summary() => DocumentSummary(
  document: Document(
    id: 7, name: 'Lease Agreement',
    createdAt: DateTime(2026, 7, 8), modifiedAt: DateTime(2026, 7, 8)),
  pageCount: 6, thumbnailPath: null); // null path -> placeholder (no file I/O)

void main() {
  testWidgets('renders title, page/date meta, and fires onTap', (tester) async {
    var opened = false;
    await pumpReam(tester, DocumentGridCard(
      summary: _summary(), onTap: () => opened = true));
    expect(find.text('Lease Agreement'), findsOneWidget);
    expect(find.textContaining('6'), findsWidgets); // "6p ·" meta
    await tester.tap(find.byKey(const Key('document-card-7')));
    expect(opened, true);
  });
}
```

*(Confirm the `Document` constructor field names against `lib/features/library/document.dart` before finalizing the test; adjust the fixture to match.)*

- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** a `StatelessWidget` matching the design's grid card
  (white/`surface` card, 1px `line` border, radius 9, soft shadow; body = mini
  page-line placeholder via `DocumentThumbnail` when a path exists else the
  neutral placeholder; footer = title + `ReamTypography.mono` meta). Wrap in
  `GestureDetector(key: Key('document-card-${id}'), onTap:, onLongPress:)`. Show a
  check badge when `selected`.
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): DocumentGridCard`).

---

## Task 11: `DocumentsGridView`  *(Wave 1 — run after Task 10)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/documents_grid_view.dart`
- Test: `apps/mobile/test/features/library/documents_grid_view_test.dart`

**Interfaces:**
- Consumes: `DocumentGridCard` (Task 10), `DocumentSummary`.
- Produces: `class DocumentsGridView extends StatelessWidget` — same public API
  shape as `DocumentsListView` (`summaries`, `onOpen`, `onRename`, `onShare`,
  `selectedIds`, `selectionMode`, `onToggleSelect`, `onLongPress`) rendered as a
  2-column `GridView`. Root key `documents-grid`.

- [ ] **Step 1: Failing test** — pump with two summaries; assert
  `find.byKey(const Key('documents-grid'))` and both card keys present; tapping a
  card calls `onOpen`.
- [ ] **Step 2: Run — expect FAIL.**
- [ ] **Step 3: Implement** a `GridView.builder` (crossAxisCount 2, childAspect
  ~0.62, padding 18/gap 14) mapping each summary to a `DocumentGridCard` wired to
  the callbacks (tap → `onToggleSelect` in selection mode else `onOpen`).
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): DocumentsGridView (2-column)`).

---

## Task 12: `SortPill`  *(Wave 1 — parallel)*

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/sort_pill.dart`
- Test: `apps/mobile/test/features/library/sort_pill_test.dart`

**Interfaces:**
- Consumes: `DocumentSort`, `SortCriterion`, `SortDirection` from
  `document_sort.dart`; `context.ream`.
- Produces: `class SortPill extends StatelessWidget` with
  `SortPill({required DocumentSort sort, required ValueChanged<SortCriterion>
  onCriterionSelected, Key? key})`. Shows the active criterion label + a
  direction arrow in a pill (key `sort-pill`); tapping opens a `PopupMenuButton`
  menu with items Name/Created/Modified (item keys `sort-option-name`, etc.).
  Selecting one calls `onCriterionSelected`. Keeps existing `document_sort`
  semantics (parent calls `nextSort`).

- [ ] **Step 1: Failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_sort.dart';
import 'package:mobile/features/library/widgets/sort_pill.dart';
import '../../support/ream_pump.dart';

void main() {
  testWidgets('shows active criterion and selects from menu', (tester) async {
    SortCriterion? picked;
    await pumpReam(tester, SortPill(
      sort: DocumentSort.initial,
      onCriterionSelected: (c) => picked = c));
    // DocumentSort.initial == (SortCriterion.created, desc)
    expect(find.text('Created'), findsOneWidget);
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name')));
    await tester.pumpAndSettle();
    expect(picked, SortCriterion.name);
  });
}
```

The three criteria are `SortCriterion.{name, created, modified}`; pill labels are
"Name" / "Created" / "Modified". `DocumentSort.initial` is Created/desc, so the
pill shows "Created" with a `↓` arrow.

- [ ] **Step 2: Run — expect FAIL.**  **Step 3:** implement the pill + popup menu.
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(library): SortPill (compact sort control)`).

---

## Task 13: Restyle `DonationBanner`  *(Wave 1 — parallel; modifies existing)*

**Files:**
- Modify: `apps/mobile/lib/features/donation/donation_banner.dart`
- Test: `apps/mobile/test/features/library/donation_banner_test.dart` (create if
  absent) — keep `s1_donation_banner` behavior intact.

**Interfaces:**
- Consumes: `context.ream`.
- Produces: same public widget (`DonationBanner`, key `donation-banner`, taps →
  `DonationScreen`) restyled to the amber card (`amberSoft` bg, amber border,
  ink2 copy, heart + chevron). **Preserve the `donation-banner` key** so
  `s1_donation_banner` + `i_tap_the_donation_banner` step keep passing.

- [ ] **Step 1: Failing/again-green test** — pump `DonationBanner` via `pumpReam`;
  assert key `donation-banner` present and its container color is
  `ReamColors.light.amberSoft`.
- [ ] **Step 2: Run — expect FAIL** (color assertion).  **Step 3:** restyle using
  `context.ream` amber tokens, keeping the `InkWell(key: Key('donation-banner'))`
  → `DonationScreen` navigation and `SafeArea(top: false)`.
- [ ] **Step 4: Run — expect PASS.**  **Step 5:** analyze + format + commit
  (`feat(donation): restyle DonationBanner to Ream amber`).

---

## Task 14: `HomeScreen` restructure + host-test updates  *(Wave 2 — single owner)*

**Files:**
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Modify (tests, failing-first): `test/features/library/home_screen_test.dart`,
  `home_search_test.dart`, `home_scan_id_test.dart`, `home_screen_import_test.dart`,
  `home_feedback_menu_test.dart`, `home_multi_export_test.dart`, `home_share_test.dart`
- Consumes: Tasks 4–13 (theme + all widgets).

**Target structure** (replaces the Material `AppBar` + extended FAB):

- A custom scrolling `CustomScrollView`/`Column` with a **paper header**:
  - Row: title "Documents" (`headlineMedium`) + subtitle "Private · on this device"
    (lock glyph + `muted`), and a **settings gear** `IconButton`
    (key `home-settings`) top-right that opens a menu; when `_feedbackAvailable`,
    the menu contains **Send feedback** (keys `home-menu-feedback` preserved,
    `home-overflow-menu` moves onto the gear).
  - `ReamSearchField` (key `documents-search-field`) always visible, wired to
    `_onQueryChanged`. Remove the AppBar search-mode (`_openSearch`/`_closeSearch`,
    `_buildSearchAppBar`, `_searching`). Filtering rule: `_query.trim().isEmpty`
    → sorted full list; else FTS results (keep the race guard).
  - Controls row: `SortPill` (key `sort-pill`, → `_onSortCriterion`) +
    `ReamSegmented` (key `library-view-toggle`, values `list`/`grid`) bound to a
    new `LibraryViewMode _viewMode = LibraryViewMode.list` (in-memory).
- **Body:** `_viewMode == list` → `DocumentsListView`; else `DocumentsGridView`
  (both fed `_displayed`). Empty → `EmptyDocumentsView`; loading spinner
  (`documents-loading`) and error (`documents-error`/`documents-retry`) preserved.
- **Bottom** (`bottomNavigationBar` or a pinned column): a **3-button action row**
  — `ReamActionButton(primary, key 'home-scan', label 'Scan', onPressed
  _openScan)`, `ReamActionButton(key 'home-scan-id', label 'ID card', onPressed
  _openIdScan)`, `ReamActionButton(key 'home-import', label 'Import', onPressed
  _onImport)` — above the restyled `DonationBanner`. Remove the extended FAB.
- **Selection mode:** when `_selectionMode`, swap the header's title row for a
  contextual bar (key `selection-bar`) with a close (`selection-close`) + export
  (`selection-export`) action, reusing `_clearSelection`/`_exportSelected`. The
  bottom action row + search hide during selection.
- **Preserve keys** used by tests: `home-scan-id`, `home-import`, `documents-list`,
  `documents-loading`, `documents-error`, `documents-retry`, `donation-banner`,
  `home-menu-feedback`, `selection-close`, `selection-export`. **New keys:**
  `home-scan`, `home-settings`, `library-view-toggle`, `documents-grid`,
  `documents-search-field`, `sort-pill`, `selection-bar`.

- [ ] **Step 1: Update host tests failing-first.** Rewrite finders in the listed
  test files to the new structure: search via `enterText` on
  `Key('documents-search-field')` (not opening a search icon); scan-id/import via
  the bottom `Key('home-scan-id')`/`Key('home-import')` buttons; feedback via the
  gear menu (`home-settings` → `home-menu-feedback`); add a test that the
  `library-view-toggle` switches to `documents-grid` and a saved doc's card shows.
  Keep each file's existing scenarios (rename/share/multi-export/sort) but retarget
  finders. Run the suite and **paste the failures**:

```bash
cd apps/mobile && flutter test test/features/library/home_screen_test.dart \
  test/features/library/home_search_test.dart \
  test/features/library/home_scan_id_test.dart \
  test/features/library/home_screen_import_test.dart \
  test/features/library/home_feedback_menu_test.dart \
  test/features/library/home_multi_export_test.dart \
  test/features/library/home_share_test.dart
```
Expected: FAIL (old structure gone / new keys missing).

- [ ] **Step 2: Implement the restructure** in `home_screen.dart` per the target
  above. Keep all state/handlers (`_init`, `_load`, `_openScan`, `_openIdScan`,
  `_onImport`, `_onQueryChanged`, `_onSortCriterion`, selection, `_refresh`,
  cold-start watchdog). Add `LibraryViewMode` enum (in this file or a small new
  `library_view_mode.dart`) and `_viewMode` state + toggle handler.
- [ ] **Step 3: Run the listed tests — expect PASS.** Paste output.
- [ ] **Step 4: Full host suite + analyze + format:**

```bash
cd apps/mobile && flutter test && flutter analyze && dart format lib test
```
Expected: all green; "No issues found!".

- [ ] **Step 5: Commit** (`feat(library): restructure HomeScreen to Ream layout
  (inline search, grid toggle, action row)`).

---

## Task 15: Restyle `DocumentsListView` rows  *(Wave 2 — same owner as Task 14, do FIRST)*

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Modify: `test/features/library/documents_list_view_test.dart`,
  `documents_list_view_selection_test.dart`

**Interfaces:**
- Unchanged public API. Rows restyled to the design: paper card row (radius 14),
  `DocumentThumbnail` in a `line`-bordered frame, title `titleMedium`, mono meta
  `N pages · <date>` via `ReamTypography.mono`, `⋯` overflow (keep
  `document-menu-<id>`, `document-rename-<id>`, `document-share-<id>` keys).
  **Preserve** `documents-list`, `document-tile-<id>`, `document-thumb-<id>`,
  `document-check-<id>` keys.

- [ ] **Step 1:** Adjust the two test files failing-first for any restyle
  assertions (e.g. mono meta text still `6 pages`), keeping selection behavior.
  Run → paste FAIL.
- [ ] **Step 2:** Restyle the `itemBuilder` (keep `ListTile` semantics or move to a
  custom row; keep all keys + callbacks). Meta line format stays
  `${date} · ${_pages(n)}` so existing text finders pass.
- [ ] **Step 3:** Run the two files — expect PASS.  **Step 4:** analyze + format +
  commit (`feat(library): restyle document rows to Ream`).

---

## Task 16: BDD features + steps + regen  *(Wave 3)*

**Files:**
- Create: `apps/mobile/integration_test/ui1_library_grid.feature`
- Create steps in `apps/mobile/test/step/`: `i_switch_to_grid_view.dart`,
  `i_see_the_document_in_grid.dart` (+ any new phrasing).
- Modify: `integration_test/d3_sort.feature` steps mapping (adapt
  `i_tap_the_sort_chip.dart` + `i_see_the_sort_chip_is_active.dart` to `SortPill`);
  verify `s1_donation_banner.feature`, `o5_content_search.feature`,
  `i2_gallery_import.feature`, `id_scan.feature` steps still resolve to the new UI.
- Regenerate: `dart run build_runner build --delete-conflicting-outputs`.

- [ ] **Step 1:** Write `ui1_library_grid.feature`:

```gherkin
Feature: Library grid view
  Scenario: Switch the library to grid and see a saved document
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I switch to grid view
    Then I see the document in grid
```

- [ ] **Step 2:** Implement the two new step files (tap `Key('library-view-toggle')`
  → `segment-grid`; assert `Key('documents-grid')` + the doc card). Update the
  sort steps to drive `SortPill`.
- [ ] **Step 3:** Regenerate + run the affected generated widget-mode tests on host
  where they don't need native libs; run:

```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
flutter test test/  # host suite incl. generated widget-mode specs that don't need native libs
```
Expected: green (OpenCV-dependent specs excluded per Global Constraints).

- [ ] **Step 4:** analyze + format + commit (`test(library): BDD grid view + adapt
  sort/donation/search steps`).

---

## Task 17: Host gate  *(Wave 3)*

- [ ] **Step 1:** `cd apps/mobile && flutter analyze` → "No issues found!".
- [ ] **Step 2:** `dart format --set-exit-if-changed lib test` → no changes.
- [ ] **Step 3:** `flutter test` → full host suite green. Paste the summary line.
- [ ] **Step 4:** If anything is red that is *environmental* (libdartcv), name it
  explicitly in the report; do not mark done silently.

---

## Task 18: Device verification (Android + iOS)  *(Wave 3 — gated on real devices)*

**Non-negotiable:** the Library is native-dependent (drift/sqlite, JPEG thumbnail
decode). Prove it on a real Android **and** a real iOS device.

- [ ] **Step 1: Discover devices:** `cd apps/mobile && flutter devices`. Record the
  Android + iOS device ids. If a platform has **no** attached device, STOP and
  report it as a **named gap** (do not fake it).
- [ ] **Step 2: Android** — run the library integration features:

```bash
cd apps/mobile && for f in b2_restart_persistence d3_sort s1_donation_banner \
  o5_content_search i2_gallery_import ui1_library_grid; do
  flutter test integration_test/${f}_test.dart -d <android-device-id> || break
done
```
Expected: each PASS. Paste the summary lines.

- [ ] **Step 3: iOS** — same loop with `-d <ios-device-id>`. Paste results.
- [ ] **Step 4:** Also do a manual smoke: `flutter run -d <id>`, confirm the Library
  renders the Ream paper header, inline search filters, grid toggle works, bottom
  action row launches Scan/ID/Import, donation banner opens. Screenshot each
  platform.
- [ ] **Step 5:** Report the exact commands + green output + screenshots. Only now
  is Phase 1 **done**. Commit any test-only fixups (`test(library): device-verify
  Ream Library on Android+iOS`).

---

## Self-review (author checklist — completed)

- **Spec coverage:** design system (Tasks 1–5), each core component (6–9, 12),
  grid (10–11), donation restyle (13), Library restructure + inline search + grid
  + action row (14–15), go-live theme wiring (Task 4), BDD (16), both-platform
  device proof (18). Dark theme = stub token set (Task 2) per spec non-goal.
- **Placeholder scan:** none — every code step has real code or an explicit,
  bounded instruction with the exact keys/signatures; two fixtures carry a
  "verify field names against the source" note (Document ctor, DocumentSort.initial
  label) because those are existing types the implementer must match.
- **Type consistency:** `ReamColors`/`context.ream`, `ReamTypography.mono`,
  `ConfidenceLevel`, `ReamSegment<T>`/`ReamSegmented<T>`, `ReamActionButton`,
  `DocumentGridCard`/`DocumentsGridView`, `SortPill`, `LibraryViewMode` names are
  used identically across producing and consuming tasks.
