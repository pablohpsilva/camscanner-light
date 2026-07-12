# Ream Phase 2 — Remaining Screen Re-skins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin five screens (04 Review-crop, 07 OCR text, 08 PDF viewer, 09 Feedback, 10 Donation) into the Ream visual language, changing only presentation — never behavior, wiring, or DI.

**Architecture:** A task-0 barrier adds/extends shared Ream widgets (`ReamBackHeader`, `ReamSectionLabel`, a `fillColor` variant on `ReamActionButton`, an `expanded` mode on `ReamSegmented`). Then one independent task per screen consumes those widgets. Light screens (07/08/09/10) use `context.ream` tokens directly under the app's light theme; the dark screen (04) wraps its subtree in `Theme(data: ReamTheme.dark())` + `AnnotatedRegion(SystemUiOverlayStyle.light)`, exactly as the shipped editor (`page_viewer_screen.dart:610-618`).

**Tech Stack:** Flutter, Material 3, `ReamColors` ThemeExtension, Figtree/IBM Plex Mono bundled fonts, `flutter_test` widget tests.

## Global Constraints

- **Pure re-skin only.** No behavior/logic/wiring/DI/callback changes. All existing unit/feature/step tests must stay green with, at most, *minimal noted finder updates* (e.g. a Material `AppBar` title finder → the Ream header). Never weaken an assertion.
- **Design source of truth:** `docs/design/ream/Ream Scanner.dc.html` (anchors 04 lines 200-234, 07 lines 300-319, 08 lines 321-341, 09 lines 342-374, 10 lines 376-402) and `docs/design/ream/README.md`. Do not re-fetch from the network.
- **Token access:** `final r = context.ream;` at build scope, then `r.paper`, `r.ink`, etc. No `ReamColors` import needed in screen files. 18 tokens: `paper, surface, surface2, ink, ink2, muted, line, line2, appBg, green, greenDeep, greenSoft, amber, amberSoft, blue, blueSoft, kofiRed, deleteRed`.
- **Type:** Figtree UI (titles w800, tracking -0.02em); IBM Plex Mono via `ReamTypography.mono(...)` for caps section-labels + technical readouts.
- **Preserve all existing widget keys** listed per task so downstream tests and integration steps keep matching.
- **Verify-then-claim:** each task runs `flutter test <files>`, `flutter analyze` (zero warnings), `dart format lib test`. Paste FAIL→PASS. Scoped `git add` — named paths only, NEVER `-A` (repo carries a long-lived WIP pile).
- **Commands run from** `apps/mobile/`.
- **Do NOT touch** `donation_banner.dart` (already Ream), `CropOverlay` gesture code, `FeedbackService`/`DonationConfig`/OCR/PDF/share plumbing, or any `*Dependencies` class.

---

### Task 0: Shared Ream widgets (barrier — merge before screen tasks)

**Files:**
- Create: `lib/theme/widgets/ream_back_header.dart`
- Create: `lib/theme/widgets/ream_section_label.dart`
- Modify: `lib/theme/widgets/ream_action_button.dart` (add `fillColor`)
- Modify: `lib/theme/widgets/ream_segmented.dart` (add `expanded`)
- Test: `test/theme/widgets/ream_back_header_test.dart`
- Test: `test/theme/widgets/ream_section_label_test.dart`
- Test: `test/theme/widgets/ream_action_button_test.dart` (create or extend if present)
- Test: `test/theme/widgets/ream_segmented_test.dart` (create or extend if present)

**Interfaces produced (later tasks rely on these exact signatures):**
- `ReamBackHeader({required String title, VoidCallback? onBack, Widget? trailing, Key? backKey}) implements PreferredSizeWidget` — leading chevron (`Key` = `backKey ?? const Key('ream-back')`), centered Figtree-700 17px title, trailing spacer/`trailing`. `onBack` defaults to `Navigator.maybePop`.
- `ReamSectionLabel(String text, {Key? key})` — renders `text.toUpperCase()` in `ReamTypography.mono(size: 11, weight: FontWeight.w600, color: r.muted, letterSpacing: 0.3)`.
- `ReamActionButton(... , Color? fillColor)` — when `primary`, fills `fillColor ?? r.greenDeep` (white label/icon retained). Secondary unchanged.
- `ReamSegmented(... , bool expanded = false)` — when true, segments are `Expanded` with centered text (full-width equal thirds). Each segment keeps `Key('segment-$value')`.

- [ ] **Step 1: Write failing test for ReamBackHeader**

`test/theme/widgets/ream_back_header_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_back_header.dart';

void main() {
  testWidgets('shows title, default back key, fires onBack', (tester) async {
    var popped = false;
    await tester.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: Scaffold(
        appBar: ReamBackHeader(title: 'Export as PDF', onBack: () => popped = true),
      ),
    ));
    expect(find.text('Export as PDF'), findsOneWidget);
    expect(find.byKey(const Key('ream-back')), findsOneWidget);
    await tester.tap(find.byKey(const Key('ream-back')));
    expect(popped, isTrue);
  });

  testWidgets('honours a custom backKey', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: Scaffold(
        appBar: ReamBackHeader(
          title: 'X',
          backKey: const Key('recognized-text-back'),
          onBack: () {},
        ),
      ),
    ));
    expect(find.byKey(const Key('recognized-text-back')), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/theme/widgets/ream_back_header_test.dart`
Expected: FAIL — `ream_back_header.dart` / `ReamBackHeader` not found.

- [ ] **Step 3: Implement ReamBackHeader**

`lib/theme/widgets/ream_back_header.dart`:

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';

/// Shared back-header for Ream screens: leading chevron, centered Figtree-700
/// title, trailing spacer (or [trailing]) for symmetry. Reads [context.ream]
/// so it renders correctly under both light and dark Ream themes.
class ReamBackHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final VoidCallback? onBack;
  final Widget? trailing;
  final Key? backKey;
  const ReamBackHeader({
    super.key,
    required this.title,
    this.onBack,
    this.trailing,
    this.backKey,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    const double sideWidth = kMinInteractiveDimension;
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: kToolbarHeight,
        child: ColoredBox(
          color: r.paper,
          child: Row(
            children: [
              SizedBox(
                width: sideWidth,
                child: IconButton(
                  key: backKey ?? const Key('ream-back'),
                  icon: const Icon(Icons.arrow_back_ios_new),
                  color: r.ink,
                  onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Figtree',
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: r.ink,
                  ),
                ),
              ),
              SizedBox(
                width: sideWidth,
                child: trailing != null
                    ? Center(child: trailing)
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test, verify pass**

Run: `flutter test test/theme/widgets/ream_back_header_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Write failing test for ReamSectionLabel**

`test/theme/widgets/ream_section_label_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_section_label.dart';

void main() {
  testWidgets('uppercases the label and uses the mono font', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: const Scaffold(body: ReamSectionLabel('Quality')),
    ));
    final text = tester.widget<Text>(find.text('QUALITY'));
    expect(text.style!.fontFamily, 'IBMPlexMono');
  });
}
```

- [ ] **Step 6: Run it, verify it fails**

Run: `flutter test test/theme/widgets/ream_section_label_test.dart`
Expected: FAIL — not found.

- [ ] **Step 7: Implement ReamSectionLabel**

`lib/theme/widgets/ream_section_label.dart`:

```dart
import 'package:flutter/material.dart';
import '../ream_colors.dart';
import '../ream_typography.dart';

/// A mono, muted, letter-spaced caps section label (e.g. QUALITY, TYPE, MESSAGE).
class ReamSectionLabel extends StatelessWidget {
  final String text;
  const ReamSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    return Text(
      text.toUpperCase(),
      style: ReamTypography.mono(
        size: 11,
        weight: FontWeight.w600,
        color: r.muted,
        letterSpacing: 0.3,
      ),
    );
  }
}
```

- [ ] **Step 8: Run test, verify pass**

Run: `flutter test test/theme/widgets/ream_section_label_test.dart`
Expected: PASS.

- [ ] **Step 9: Add `fillColor` to ReamActionButton (failing test first)**

Append to `test/theme/widgets/ream_action_button_test.dart` (create the file with this content if absent):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_action_button.dart';

void main() {
  testWidgets('primary honours a custom fillColor', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: Scaffold(
        body: ReamActionButton(
          label: 'Send report',
          primary: true,
          fillColor: ReamColors.light.ink,
          onPressed: () {},
        ),
      ),
    ));
    final material = tester.widget<Material>(
      find.descendant(of: find.byType(ReamActionButton), matching: find.byType(Material)),
    );
    expect(material.color, ReamColors.light.ink);
  });
}
```

- [ ] **Step 10: Run it, verify it fails**

Run: `flutter test test/theme/widgets/ream_action_button_test.dart`
Expected: FAIL — `fillColor` is not a named parameter.

- [ ] **Step 11: Implement `fillColor`**

In `lib/theme/widgets/ream_action_button.dart`: add the field and use it for the primary fill.

Add field (next to `primary`):
```dart
  /// Overrides the primary fill (default = greenDeep). No effect when secondary.
  final Color? fillColor;
```
Add to the constructor param list: `this.fillColor,`
Change the `Material`'s color line from:
```dart
        color: primary ? r.greenDeep : r.surface,
```
to:
```dart
        color: primary ? (fillColor ?? r.greenDeep) : r.surface,
```

- [ ] **Step 12: Run test, verify pass**

Run: `flutter test test/theme/widgets/ream_action_button_test.dart`
Expected: PASS.

- [ ] **Step 13: Add `expanded` to ReamSegmented (failing test first)**

Append to `test/theme/widgets/ream_segmented_test.dart` (create with this content if absent):

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:mobile/theme/widgets/ream_segmented.dart';

void main() {
  testWidgets('expanded lays out full-width segments; tap fires onChanged',
      (tester) async {
    String? picked;
    await tester.pumpWidget(MaterialApp(
      theme: ReamTheme.light(),
      home: Scaffold(
        body: ReamSegmented<String>(
          expanded: true,
          value: 'bug',
          segments: const [
            ReamSegment(value: 'bug', label: 'Bug'),
            ReamSegment(value: 'idea', label: 'Idea'),
            ReamSegment(value: 'question', label: 'Question'),
          ],
          onChanged: (v) => picked = v,
        ),
      ),
    ));
    expect(find.byType(Expanded), findsNWidgets(3));
    await tester.tap(find.byKey(const Key('segment-idea')));
    expect(picked, 'idea');
  });
}
```

- [ ] **Step 14: Run it, verify it fails**

Run: `flutter test test/theme/widgets/ream_segmented_test.dart`
Expected: FAIL — `expanded` is not a named parameter (and no `Expanded` in tree).

- [ ] **Step 15: Implement `expanded`**

In `lib/theme/widgets/ream_segmented.dart`: add `final bool expanded;` (default `false`) to fields + constructor. Extract the per-segment tappable into a private method and wrap in `Expanded` when `expanded`. Replace the `Row`'s `children` build with:

```dart
      child: Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        children: [
          for (final s in segments)
            if (expanded) Expanded(child: _segment(context, s)) else _segment(context, s),
        ],
      ),
```

and add:

```dart
  Widget _segment(BuildContext context, ReamSegment<T> s) {
    final r = context.ream;
    final selected = s.value == value;
    return GestureDetector(
      key: Key('segment-${s.value}'),
      onTap: () => onChanged(s.value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? r.ink : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          s.label,
          style: TextStyle(
            fontFamily: 'Figtree',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: selected ? r.surface : r.muted,
          ),
        ),
      ),
    );
  }
```

- [ ] **Step 16: Run tests, verify pass**

Run: `flutter test test/theme/widgets/`
Expected: PASS (all widget tests, including any pre-existing ones unchanged).

- [ ] **Step 17: Analyze, format, commit**

```bash
flutter analyze lib/theme test/theme
dart format lib/theme test/theme
git add lib/theme/widgets/ream_back_header.dart lib/theme/widgets/ream_section_label.dart lib/theme/widgets/ream_action_button.dart lib/theme/widgets/ream_segmented.dart test/theme/widgets/ream_back_header_test.dart test/theme/widgets/ream_section_label_test.dart test/theme/widgets/ream_action_button_test.dart test/theme/widgets/ream_segmented_test.dart
git commit -m "feat(theme): shared Ream widgets for Phase 2 screens (back header, section label, button fill, segmented expand)"
```

---

### Task 1: Screen 07 — Recognized text (OCR), light

**Files:**
- Modify: `lib/features/library/recognized_text_screen.dart`
- Test: `test/features/library/recognized_text_screen_test.dart` (adjust finders as noted)

**Interfaces consumed:** `ReamBackHeader`, `ConfidenceChip`, `ReamActionButton`.

**Design:** `.dc.html` lines 300-319. Light `r.paper` bg; Ream header "Recognized text"; when text exists, a green **ConfidenceChip** "Text layer ready · powers search" above the body; `SelectableText` restyled Figtree 13/1.7 `r.ink2`; footer two buttons — **Copy text** (secondary surface) and **Share .txt** (primary, `fillColor: r.ink`).

**Preserve (keys + behavior):** state machine (`_load`/`_recognize`/`_copy`/`_share`), `Key('recognized-text-loading')`, `Key('recognized-text-body')`, `Key('recognized-text-empty')`, `Key('recognized-text-run')`. The copy + share actions **keep keys** `Key('recognized-text-copy')` and `Key('recognized-text-share')` — moved from `AppBar` actions onto the footer buttons; `_share` still routes through the existing share path.

- [ ] **Step 1: Write/adjust the failing widget test**

In `test/features/library/recognized_text_screen_test.dart`, add (and update any test that located the old `AppBar` title `'Text'` to expect `'Recognized text'`):

```dart
testWidgets('OCR screen uses Ream chrome: paper bg, header, confidence chip',
    (tester) async {
  // Build with a fake repository that returns a page with OCR text for
  // (documentId, position) — reuse the harness already in this file.
  // ... pump RecognizedTextScreen inside MaterialApp(theme: ReamTheme.light()) ...
  await tester.pumpAndSettle();
  expect(find.text('Recognized text'), findsOneWidget);
  expect(find.byType(ConfidenceChip), findsOneWidget);
  expect(find.byKey(const Key('recognized-text-copy')), findsOneWidget);
  expect(find.byKey(const Key('recognized-text-share')), findsOneWidget);
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  expect(scaffold.backgroundColor, ReamColors.light.paper);
});
```

Imports to add: `ream_theme.dart`, `ream_colors.dart`, `theme/widgets/confidence_chip.dart`.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/features/library/recognized_text_screen_test.dart`
Expected: FAIL — `'Recognized text'` / `ConfidenceChip` / paper bg absent.

- [ ] **Step 3: Re-skin the screen**

In `recognized_text_screen.dart` `build()`: set `Scaffold(backgroundColor: r.paper, ...)` (`final r = context.ream;`), replace `appBar: AppBar(...)` with `appBar: ReamBackHeader(title: 'Recognized text', onBack: () => Navigator.of(context).maybePop(), backKey: const Key('recognized-text-back'))`. Keep the three body states. In the `hasText` branch wrap the scroll body in a `Column` with, at top, `Padding(child: ConfidenceChip(level: ConfidenceLevel.high, label: 'Text layer ready · powers search'))`, then `Expanded(SingleChildScrollView(... SelectableText(text, key: Key('recognized-text-body'), style: TextStyle(fontFamily: 'Figtree', fontSize: 13, height: 1.7, color: r.ink2))))`, then a footer `Row` with two `Expanded` `ReamActionButton`s:

```dart
Expanded(child: ReamActionButton(
  key: const Key('recognized-text-copy'),
  label: 'Copy text',
  onPressed: (_busy || !hasText) ? null : _copy,
)),
const SizedBox(width: 9),
Expanded(child: ReamActionButton(
  key: const Key('recognized-text-share'),
  label: 'Share .txt', primary: true, fillColor: r.ink,
  onPressed: (_busy || !hasText) ? null : () => unawaited(_share()),
)),
```

Restyle the empty-state `FilledButton` container to `r.paper` context (leave the button; it is behavior). Remove now-unused `ShareMenuButton` import only if no longer referenced.

- [ ] **Step 4: Run the screen tests, verify pass**

Run: `flutter test test/features/library/recognized_text_screen_test.dart test/features/library/export_recognized_text_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/library/recognized_text_screen.dart
dart format lib/features/library/recognized_text_screen.dart test/features/library/recognized_text_screen_test.dart
git add lib/features/library/recognized_text_screen.dart test/features/library/recognized_text_screen_test.dart
git commit -m "feat(library): re-skin recognized text (OCR) screen to Ream"
```

---

### Task 2: Screen 08 — Export PDF viewer, light

**Files:**
- Modify: `lib/features/library/pdf_preview_screen.dart`
- Test: `test/features/library/pdf_preview_screen_test.dart`

**Interfaces consumed:** `ReamBackHeader`.

**Design:** `.dc.html` lines 321-341 depict a quality/password *options* screen — that flow lives elsewhere (export-quality) and is **out of scope**. This file is the pinch **viewer** of an already-generated PDF. Re-skin its **chrome only**: light `r.paper` bg; Ream header titled with `widget.name`; Ream-styled loading/error states. Keep `PdfViewPinch` and the existing `ShareMenuButton` action untouched.

**Preserve (keys + behavior):** `_open` state machine, `Key('pdf-preview-loading')`, `Key('pdf-preview-error')`, `Key('pdf-preview-view')`, `Key('pdf-preview-share')`, the injected `opener`/`share`.

- [ ] **Step 1: Write the failing test**

Add to `test/features/library/pdf_preview_screen_test.dart`:

```dart
testWidgets('PDF viewer uses Ream chrome (header title + paper bg)',
    (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: ReamTheme.light(),
    home: PdfPreviewScreen(
      pdfPath: '/nonexistent.pdf',
      name: 'Lease Agreement',
      opener: (_) async => throw Exception('no native in host'),
    ),
  ));
  await tester.pumpAndSettle();
  expect(find.text('Lease Agreement'), findsOneWidget);
  expect(find.byKey(const Key('ream-back')), findsOneWidget);
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  expect(scaffold.backgroundColor, ReamColors.light.paper);
  // error branch still reachable + keyed
  expect(find.byKey(const Key('pdf-preview-error')), findsOneWidget);
});
```

Imports: `ream_theme.dart`, `ream_colors.dart`.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/features/library/pdf_preview_screen_test.dart`
Expected: FAIL — Ream header/paper bg absent.

- [ ] **Step 3: Re-skin the chrome**

In `pdf_preview_screen.dart` `build()`: `final r = context.ream;`, `Scaffold(backgroundColor: r.paper, appBar: ReamBackHeader(title: widget.name, onBack: () => Navigator.of(context).maybePop(), trailing: ShareMenuButton(buttonKey: const Key('pdf-preview-share'), onShare: () => unawaited(widget.share.share([widget.pdfPath], subject: widget.name)))), body: ...)`. Restyle the error `Text` with `TextStyle(fontFamily: 'Figtree', color: r.ink2)` and keep `Key('pdf-preview-error')`; keep loading + `PdfViewPinch` branches (only the surrounding `Center`/colors change).

- [ ] **Step 4: Run test, verify pass**

Run: `flutter test test/features/library/pdf_preview_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/library/pdf_preview_screen.dart
dart format lib/features/library/pdf_preview_screen.dart test/features/library/pdf_preview_screen_test.dart
git add lib/features/library/pdf_preview_screen.dart test/features/library/pdf_preview_screen_test.dart
git commit -m "feat(library): re-skin PDF viewer chrome to Ream"
```

---

### Task 3: Screen 09 — Send feedback, light

**Files:**
- Modify: `lib/features/feedback/feedback_screen.dart`
- Test: `test/features/feedback/feedback_screen_test.dart`

**Interfaces consumed:** `ReamBackHeader`, `ReamSectionLabel`, `ReamSegmented`, `ReamActionButton`.

**Design:** `.dc.html` lines 342-374. Light `r.paper` bg; Ream header "Send feedback"; `TYPE` section label + full-width **ReamSegmented** (Bug/Idea/Question); `MESSAGE` label + restyled multiline field; `EMAIL — optional` label + field (`Colors.grey` → `r.muted`); blue "What we include" info card (`r.blueSoft` bg); primary **Send report** button (`fillColor: r.ink`).

**Preserve (keys + behavior):** `_formKey` validation, `_submit`, `_message`/`_email` controllers, `_category` value, the diagnostics disclosure toggle, the Turnstile gate (device-only branch, untouched), `Key('feedback-message')`, `Key('feedback-email')`, `Key('feedback-submit')`, `Key('feedback-diagnostics-toggle')`, `Key('feedback-email-warning')`. **Category control:** replace the `DropdownButtonFormField` with `ReamSegmented`, but keep the same `_category` state + values `bug/idea/question`. The segmented control exposes `Key('segment-bug'|'segment-idea'|'segment-question')`. Update the screen test's category interaction from opening the dropdown to `tester.tap(find.byKey(const Key('segment-idea')))`.

- [ ] **Step 1: Adjust the failing test**

In `test/features/feedback/feedback_screen_test.dart`: (a) any test asserting the old `AppBar`/dropdown must move to the Ream header + segmented control; (b) add:

```dart
testWidgets('feedback uses Ream chrome + segmented category', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: ReamTheme.light(),
    home: const FeedbackScreen(),
  ));
  expect(find.text('Send feedback'), findsOneWidget);
  expect(find.byType(ReamSegmented<String>), findsOneWidget);
  await tester.tap(find.byKey(const Key('segment-idea')));
  await tester.pump();
  // Category state now 'idea' — assert via the segmented selection styling or a
  // submit round-trip using the existing FeedbackService fake in this file.
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  expect(scaffold.backgroundColor, ReamColors.light.paper);
});
```

Imports: `ream_theme.dart`, `ream_colors.dart`, `theme/widgets/ream_segmented.dart`.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/features/feedback/feedback_screen_test.dart`
Expected: FAIL — header text / `ReamSegmented` absent.

- [ ] **Step 3: Re-skin the form**

`final r = context.ream;`. `Scaffold(backgroundColor: r.paper, appBar: ReamBackHeader(title: 'Send feedback', onBack: () => Navigator.of(context).maybePop()), body: ...)`. Replace the dropdown block with:

```dart
const ReamSectionLabel('Type'),
const SizedBox(height: 8),
ReamSegmented<String>(
  expanded: true,
  value: _category,
  segments: const [
    ReamSegment(value: 'bug', label: 'Bug'),
    ReamSegment(value: 'idea', label: 'Idea'),
    ReamSegment(value: 'question', label: 'Question'),
  ],
  onChanged: (v) => setState(() => _category = v),
),
```

Wrap `MESSAGE` and `EMAIL` fields each with a leading `ReamSectionLabel`; give the message/email `TextFormField`s a Ream `InputDecoration` (`filled: true, fillColor: r.surface`, `OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: r.line))`). Change the email-warning `Text` color `Colors.grey` → `r.muted`. Restyle the diagnostics disclosure (when shown) into a `r.blueSoft` card with a blue dot header. Replace the submit `FilledButton` with `ReamActionButton(key: const Key('feedback-submit'), label: 'Send report', primary: true, fillColor: r.ink, onPressed: _submitting ? null : _submit)` — keep the busy spinner by showing it via `_submitting` (wrap: when submitting, render a keyed disabled button with a small spinner child instead — preserve `Key('feedback-submit')`).

- [ ] **Step 4: Run the feedback tests, verify pass**

Run: `flutter test test/features/feedback/`
Expected: PASS (all feedback unit tests).

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/feedback/feedback_screen.dart
dart format lib/features/feedback/feedback_screen.dart test/features/feedback/feedback_screen_test.dart
git add lib/features/feedback/feedback_screen.dart test/features/feedback/feedback_screen_test.dart
git commit -m "feat(feedback): re-skin feedback screen to Ream"
```

---

### Task 4: Screen 10 — Support / donation, light

**Files:**
- Modify: `lib/features/donation/donation_screen.dart`
- Test: `test/features/donation/donation_screen_test.dart`

**Interfaces consumed:** `ReamBackHeader`, `ReamActionButton`.

**Design:** `.dc.html` lines 376-402. Light `r.paper` bg; Ream header "Support Ream"; centered ♥ + Figtree-800 headline + `r.ink2` body; amber honest-disclaimer card (`r.amberSoft`); **Ko-fi** button (`ReamActionButton primary, fillColor: r.kofiRed`, icon coffee); Bitcoin card (`r.surface`/`r.line`) with QR (white quiet-zone kept — QR requires it), mono truncated address + green-deep "copy".

**Preserve (keys + behavior):** `_openKofi`, `_copyAddress`, config-driven visibility (`kofiUrl`/`bitcoinAddress` empty → hidden), `Key('donation-kofi-button')`, `Key('donation-bitcoin-section')`, `Key('donation-bitcoin-copy')`. Replace `Colors.amber.shade700` (heart) with `r.amber`/`r.kofiRed`; keep `Colors.white` **only** as the QR container background (QR readability requires a white quiet zone).

- [ ] **Step 1: Write the failing test**

Add to `test/features/donation/donation_screen_test.dart`:

```dart
testWidgets('donation uses Ream chrome (header + paper bg)', (tester) async {
  await tester.pumpWidget(MaterialApp(
    theme: ReamTheme.light(),
    home: const DonationScreen(kofiUrl: 'https://ko-fi.com/x', bitcoinAddress: 'bc1qtest'),
  ));
  expect(find.text('Support Ream'), findsOneWidget);
  expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
  final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
  expect(scaffold.backgroundColor, ReamColors.light.paper);
});
```

Imports: `ream_theme.dart`, `ream_colors.dart`.

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/features/donation/donation_screen_test.dart`
Expected: FAIL — header/paper bg absent.

- [ ] **Step 3: Re-skin the screen**

`final r = context.ream;`. `Scaffold(backgroundColor: r.paper, appBar: ReamBackHeader(title: 'Support Ream', onBack: () => Navigator.of(context).maybePop()), body: ListView(...))`. Replace the heart `Icon(Icons.favorite, color: r.kofiRed, size: 34)`; headline `Text('No accounts. No cloud.\nNo subscription.', textAlign: center, style: TextStyle(fontFamily: 'Figtree', fontWeight: FontWeight.w800, fontSize: 21, height: 1.25, color: r.ink))`; body `r.ink2`. Add an amber disclaimer `Container(decoration: BoxDecoration(color: r.amberSoft, borderRadius: BorderRadius.circular(12), border: Border.all(color: r.amber)), ...)` with the existing "no benefits" copy. Ko-fi: `ReamActionButton(key: const Key('donation-kofi-button'), label: 'Buy me a coffee — Ko-fi', icon: Icons.local_cafe_outlined, primary: true, fillColor: r.kofiRed, onPressed: () => _openKofi(context))`. In `_BitcoinSection`, wrap in a `r.surface`/`r.line` card; keep `Container(color: Colors.white, ... QrImageView(...))`; address `ReamTypography.mono(...)`; keep `Key('donation-bitcoin-copy')` on an `OutlinedButton.icon` restyled or a secondary `ReamActionButton`.

- [ ] **Step 4: Run donation tests, verify pass**

Run: `flutter test test/features/donation/`
Expected: PASS (donation_screen + config + banner tests unchanged-green).

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/donation/donation_screen.dart
dart format lib/features/donation/donation_screen.dart test/features/donation/donation_screen_test.dart
git add lib/features/donation/donation_screen.dart test/features/donation/donation_screen_test.dart
git commit -m "feat(donation): re-skin support screen to Ream"
```

---

### Task 5: Screen 04 — Review & clean (crop editor), dark chrome-only

**Files:**
- Modify: `lib/features/library/edit_crop_screen.dart`
- Test: `test/features/library/edit_crop_screen_test.dart` (create if absent)

**Interfaces consumed:** `ReamBackHeader`, `ReamTheme.dark`.

**Design:** `.dc.html` lines 200-234 (dark). The real screen is only a crop editor (image + `CropOverlay` + Accept). **Chrome-only:** dark background via the editor idiom, dark Ream header with an Accept trailing action, themed broken-image icon. **The mockup's confidence chip / filter strip / Add-page-Save footer do not exist in this screen and are NOT added** (that would be new behavior — named gap). **Do not touch** `CropOverlay`, `_resolveImageSize`, gesture/corner logic.

**Preserve (keys + behavior):** `Key('edit-crop-image')`, `Key('edit-crop-accept')` (Accept pops with `_corners`), back pops with null, injected `decodeImageSize`.

- [ ] **Step 1: Write the failing test**

`test/features/library/edit_crop_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';
import 'package:mobile/theme/ream_colors.dart';

void main() {
  testWidgets('crop editor uses dark Ream chrome + keeps Accept', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: EditCropScreen(
        imagePath: '/nonexistent.jpg',
        initialCorners: const CropCorners(
          topLeft: Offset(0, 0), topRight: Offset(1, 0),
          bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1),
        ),
        decodeImageSize: (_) async => const Size(100, 200),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const Key('edit-crop-accept')), findsOneWidget);
    // Body background is the dark Ream paper tone, not raw Colors.black.
    final box = tester.widget<ColoredBox>(find.descendant(
      of: find.byType(Scaffold), matching: find.byType(ColoredBox)).first);
    expect(box.color, ReamColors.dark.paper);
  });
}
```

(Confirm `CropCorners`' constructor shape from `lib/features/library/crop_corners.dart` and adjust the literal to match before running.)

- [ ] **Step 2: Run it, verify it fails**

Run: `flutter test test/features/library/edit_crop_screen_test.dart`
Expected: FAIL — background is `Colors.black`, no Ream header.

- [ ] **Step 3: Re-skin the chrome**

Wrap the return in the editor's dark idiom and swap the header/background:

```dart
@override
Widget build(BuildContext context) {
  final size = _imageSize;
  return AnnotatedRegion<SystemUiOverlayStyle>(
    value: SystemUiOverlayStyle.light,
    child: Theme(
      data: ReamTheme.dark(),
      child: Builder(builder: (context) {
        final r = context.ream;
        return Scaffold(
          appBar: ReamBackHeader(
            title: 'Review & clean',
            backKey: const Key('edit-crop-back'),
            onBack: () => Navigator.of(context).pop(),
            trailing: TextButton(
              key: const Key('edit-crop-accept'),
              onPressed: () => Navigator.of(context).pop(_corners),
              child: Text('Save', style: TextStyle(color: r.green, fontFamily: 'Figtree', fontWeight: FontWeight.w700)),
            ),
          ),
          body: ColoredBox(
            color: r.paper,
            child: SizedBox.expand(
              child: size == null
                  ? Center(child: _imageWidget())
                  : CropOverlay(
                      imageSize: size,
                      image: _imageWidget(),
                      corners: _corners,
                      onCornersChanged: (c) => setState(() => _corners = c),
                    ),
            ),
          ),
        );
      }),
    ),
  );
}
```

Add imports `package:flutter/services.dart`, `../../theme/ream_colors.dart`, `../../theme/ream_theme.dart`, `../../theme/widgets/ream_back_header.dart`. In `_imageWidget`, change the broken-image icon color `Colors.white54` → a themed muted tone (pass `context.ream.muted` or keep `Colors.white54` as an acceptable dark-on-dark constant — prefer the token). Note: `ReamBackHeader.trailing` is narrow (kMinInteractiveDimension); if "Save" clips, keep the Accept action but shorten to an icon or widen — record the choice in the task review.

- [ ] **Step 4: Run test, verify pass**

Run: `flutter test test/features/library/edit_crop_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Analyze, format, commit**

```bash
flutter analyze lib/features/library/edit_crop_screen.dart
dart format lib/features/library/edit_crop_screen.dart test/features/library/edit_crop_screen_test.dart
git add lib/features/library/edit_crop_screen.dart test/features/library/edit_crop_screen_test.dart
git commit -m "feat(library): re-skin crop editor chrome to dark Ream"
```

---

### Task 6: Whole-batch verification

**Files:** none (verification only).

- [ ] **Step 1: Full host suite**

Run: `flutter test`
Expected: green except the 2 known `opencv_edge_detector_test` env failures.

- [ ] **Step 2: Analyze + format gate**

Run: `flutter analyze` (expect zero warnings) then `dart format lib test` (expect no diffs, or commit formatting).

- [ ] **Step 3: Combined Android install eyeball pass (named gap: iOS sim-only)**

```bash
flutter clean && flutter pub get && flutter build apk --release && flutter install -d <android-device-id>
```
Eyeball all five screens against the `.dc.html` anchors. Record result. iOS remains a named sim-only gap per project constraints.

## Self-Review

**Spec coverage:** 07/08/09/10 light + 04 dark chrome-only ✓ (Tasks 1-5); shared `ReamBackHeader`/`ReamSectionLabel` + button/segmented variants as task-0 barrier ✓ (Task 0); reuse of `confidence_chip`/`ream_action_button`/`ream_segmented` ✓; `donation_banner` untouched ✓; no new `.feature` files ✓; preserve-behavior + preserve-keys ✓ (per-task lists); TDD-first ✓; on-device eyeball as named gap ✓ (Task 6).

**Placeholder scan:** every step has concrete test code, real widget APIs, exact paths, and run/commit commands. The one deliberate open judgment (04 "Save" trailing fit) is flagged for task review, not left as a silent TODO.

**Type consistency:** `ReamBackHeader({title, onBack, trailing, backKey})`, `ReamSectionLabel(String)`, `ReamActionButton(..., fillColor)`, `ReamSegmented(..., expanded, Key('segment-$value'))`, `ConfidenceChip(level, label)`, `ConfidenceLevel.high` — used identically across tasks 0-5.
